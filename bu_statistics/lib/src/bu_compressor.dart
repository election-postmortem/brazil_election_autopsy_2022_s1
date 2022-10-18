import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide GZipEncoder, GZipDecoder;
import 'package:collection/collection.dart';
import 'package:lzma/lzma.dart';
import 'package:path/path.dart' as pack_path;

import 'bu_utils.dart';

enum BUCompressorType {
  bZip2,
  gZip,
  lzma,
}

typedef OnDecompressJson = void Function(String fileName, dynamic json);

typedef JsonToObject<O> = O Function(
    String fileName, Map<String, dynamic> json);

const int _mb1 = 1024 * 1024;

class BUCompressor {
  static final String version = "1.0";

  final BUCompressorType compressorType;

  BUCompressor({this.compressorType = BUCompressorType.gZip});

  _CompressorEncoder _createCompressorEncoder() {
    switch (compressorType) {
      case BUCompressorType.gZip:
        return _CompressorEncoderGzip();
      case BUCompressorType.bZip2:
        return _CompressorEncoderBZip2();
      case BUCompressorType.lzma:
        return _CompressorEncoderLzma();
    }
  }

  _CompressorDecoder _createCompressorDecoder(
      {BUCompressorType? compressorType}) {
    compressorType ??= this.compressorType;

    switch (compressorType) {
      case BUCompressorType.gZip:
        return _CompressorDecoderGzip();
      case BUCompressorType.bZip2:
        return _CompressorDecoderBZip2();
      case BUCompressorType.lzma:
        return _CompressorDecoderLzma();
    }
  }

  Future<List> decompress<O>(File inputFile,
      {OnDecompressJson? onDecompressJson,
      JsonToObject<O>? jsonToObject}) async {
    print(
        '-- Reading: ${inputFile.path} (${inputFile.lengthSync() / _mb1} MB)');

    var allData = FileBytes.fromFile(inputFile);

    var ver = allData.readString16();

    if (ver != version) {
      throw StateError("Different version: `$ver` != `$version`");
    }

    var compressorType = allData.readEnum(BUCompressorType.values);

    print('-- compressorType: $compressorType');

    var totalBlocks = allData.readInt32();

    print('-- Total compression blocks: $totalBlocks');

    var allJsons = [];

    print('-- Reading compression blocks...');

    for (var i = 0; i < totalBlocks; i += 3) {
      var blocks = [
        allData.readBlock32(),
        if (i + 1 < totalBlocks) allData.readBlock32(),
        if (i + 2 < totalBlocks) allData.readBlock32(),
      ];

      var results = await Future.wait(blocks.map(
          (block) => _decompressParallel(compressorType, block, jsonToObject)));

      var resultsJsons = results.whereNotNull().expand((l) => l);

      print('-- Block[$i/$totalBlocks]> BUs: ${resultsJsons.length}');

      allJsons.addAll(resultsJsons);

      if (onDecompressJson != null) {
        for (var e in resultsJsons) {
          var path = e[0];
          var j = e[1];
          onDecompressJson(path, j);
        }
      }
    }

    allData.close();

    return allJsons;
  }

  Future<List?> _decompressParallel<O>(BUCompressorType compressorType,
      Uint8List? blockCompressed, JsonToObject<O>? jsonToObject) async {
    if (blockCompressed == null) return null;

    return parallelCall((List args) {
      final compressorDecoder =
          _createCompressorDecoder(compressorType: args[0]);
      var list = _decompressBlock(compressorDecoder, args[1]);
      if (jsonToObject != null) {
        return list.map((e) {
          var path = e[0];
          var j = e[1];
          var o = jsonToObject(path, j);
          return [path, o];
        }).toList();
      } else {
        return list;
      }
    }, [compressorType, blockCompressed]);
  }

  List _decompressBlock(
      _CompressorDecoder compressorDecoder, Uint8List blockCompressed) {
    var blockBytes = compressorDecoder.decode(blockCompressed).toUint8List();
    var blockData = Bytes.from(blockBytes);

    var stringTable = blockData.readListOfString16();

    var blockLength = blockData.readInt16();

    var blockJsons = [];

    for (var j = 0; j < blockLength; ++j) {
      var path = blockData.readString16();
      var content = blockData.readJson(stringTable: stringTable);

      blockJsons.add([path, content]);
    }

    return blockJsons;
  }

  Future<List<File>> decompressAndSaveFiles(File inputFile,
      {Directory? outputDirectory}) async {
    outputDirectory ??= Directory('/tmp/bu-files/');

    var savedFiles = <File>[];

    await decompress(inputFile, onDecompressJson: (fileName, json) {
      var file = saveJsonFile(outputDirectory!, fileName, json);
      savedFiles.add(file);
    });

    return savedFiles;
  }

  File saveJsonFile(
      Directory outputDirectory, String fileName, Map<String, dynamic> json) {
    var file = File(pack_path.join(outputDirectory.path, fileName));

    var parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    var jsonEncoded = JsonUtf8Encoder().convert(json);
    var compressor = GZipCodec(level: 5);
    var compressed = compressor.encode(jsonEncoded);

    file.writeAsBytesSync(compressed);

    print('-- Saved: ${file.path} (${file.lengthSync()})');

    return file;
  }
}

/// Compresses a BU directory into a single [BZip2] file.
/// It will list the ".bu.json.gz" files, group them and compress into a single JSON.
class BUDirectoryCompressor extends BUCompressor {
  final Directory busDirectory;

  BUDirectoryCompressor(Directory busDirectory, {super.compressorType})
      : busDirectory = busDirectory.absolute;

  List<File>? _listFilesBUJsonGz;

  List<File> listFilesBUJsonGz() => _listFilesBUJsonGz ??=
      UnmodifiableListView(busDirectory.listFilesBUJsonGz());

  int get totalFiles => listFilesBUJsonGz().length;

  int? _totalFilesLength;

  int get totalFilesLength =>
      _totalFilesLength ??= listFilesBUJsonGz().map((f) => f.lengthSync()).sum;

  Iterable<List> _allFilesJson() {
    final dirPath = busDirectory.path;

    print('-- Reading ".bu.json.gz" files... ($dirPath)');
    var filesContent =
        listFilesBUJsonGz().map((f) => MapEntry(f, f.readCompressed()));

    var all = filesContent.map((e) {
      var f = e.key;
      var fLength = f.lengthSync();
      var bytes = e.value;
      var content = utf8.decode(bytes);

      //print("-- Encoding ${f.path}...");

      var path = f.path;

      if (!path.startsWith(dirPath)) {
        throw StateError("Not a sub-file: $f");
      }

      path = path.substring(dirPath.length);
      while (path.startsWith('/')) {
        path = path.substring(1);
      }

      var j = json.decode(content);

      return [path, j, bytes.length, fLength];
    });

    return all;
  }

  Uint8List compressAllJsons() {
    var allJsons = _allFilesJson();

    var allBlocks = allJsons.splitBeforeIndexed((i, e) => i % 300 == 0);

    var allData = Bytes(capacity: _mb1);

    allData.writeString16(BUCompressor.version);
    allData.writeEnum(compressorType);

    var blocksLengthPosition = allData.position;
    allData.writeInt32(0);

    var compressorEncoder = _createCompressorEncoder();
    print('-- compressorType: $compressorType');

    var blockI = 0;
    var fileI = 0;
    var processedBytes = 0;
    var processedGzipBytes = 0;

    var blockData = Bytes(capacity: _mb1 * 4);

    var initTime = DateTime.now();

    for (var block in allBlocks) {
      blockData.reset();

      var stringTable = blockData.buildStringTable(block)..sort();
      blockData.writeListOfString16(stringTable);

      blockData.writeInt16(block.length);

      var fileInit = fileI;

      for (var e in block) {
        var path = e[0] as String;
        var content = e[1] as Map;
        var contentBytesLength = e[2] as int;
        var contentGzipBytesLength = e[3] as int;

        blockData.writeString16(path);
        blockData.writeJson(content, stringTable: stringTable);

        ++fileI;
        processedBytes += contentBytesLength;
        processedGzipBytes += contentGzipBytesLength;
      }

      var blockBytes = blockData.toBytes();
      print(
          '-- Compressing block[$blockI]{files: $fileInit .. $fileI} (blockData: ${blockBytes.length} bytes ; allData: ${allData.size} bytes)...');

      var blockCompressed = compressorEncoder.encode(blockBytes);
      var blockCompressionRatio = blockCompressed.length / blockBytes.length;

      print(
          '-- Compressed block[$blockI]: ${blockCompressed.length} bytes (${blockCompressionRatio.toStrFixed(4)})');

      allData.writeBlock32(blockCompressed);
      print('-- Buffer size: ${allData.size ~/ _mb1} MB ; '
          'Processed GZip bytes: ${processedGzipBytes ~/ _mb1} MB (${(allData.size / processedGzipBytes).toStrFixed(4)}) ; '
          'Processed bytes: ${processedBytes ~/ _mb1} MB (${(allData.size / processedBytes).toStrFixed(4)})');

      ++blockI;

      var elapsedTime = DateTime.now().difference(initTime);
      var speed = fileI / elapsedTime.inSeconds;

      print('-- Speed: ${speed.toStrFixed(4)} files/sec');
    }

    allData.seek(blocksLengthPosition);
    allData.writeInt32(blockI);

    return allData.toBytes();
  }

  /// Compresses [busDirectory] to an [outputFile].
  int compress(File outputFile) {
    var totalFilesMB = totalFilesLength ~/ _mb1;

    print('-- Total files: $totalFiles ($totalFilesMB MB)');

    var jsonCompressed = compressAllJsons();

    var jsonCompressedMB = jsonCompressed.length ~/ _mb1;

    print('-- JSON compressed: $jsonCompressedMB MB / $totalFilesMB MB');

    var ratio = jsonCompressed.length / totalFilesLength;

    print('-- Compression ratio: $ratio');

    outputFile.writeAsBytesSync(jsonCompressed);

    return jsonCompressed.length;
  }

  @override
  Future<List<File>> decompressAndSaveFiles(File inputFile,
      {Directory? outputDirectory}) {
    outputDirectory ??= busDirectory;
    return super
        .decompressAndSaveFiles(inputFile, outputDirectory: outputDirectory);
  }
}

abstract class _CompressorEncoder {
  List<int> encode(List<int> data);
}

abstract class _CompressorDecoder {
  List<int> decode(List<int> data);
}

class _CompressorEncoderBZip2 implements _CompressorEncoder {
  final _encoder = BZip2Encoder();

  @override
  List<int> encode(List<int> data) => _encoder.encode(data);
}

class _CompressorDecoderBZip2 implements _CompressorDecoder {
  final _decoder = BZip2Decoder();

  @override
  List<int> decode(List<int> data) => _decoder.decodeBytes(data);
}

class _CompressorEncoderGzip implements _CompressorEncoder {
  final _encoder = GZipCodec(level: 5);

  @override
  List<int> encode(List<int> data) => _encoder.encode(data);
}

class _CompressorDecoderGzip implements _CompressorDecoder {
  final _decoder = GZipCodec(level: 5);

  @override
  List<int> decode(List<int> data) => _decoder.decode(data);
}

class _CompressorEncoderLzma implements _CompressorEncoder {
  @override
  List<int> encode(List<int> data) => lzma.encode(data);
}

class _CompressorDecoderLzma implements _CompressorDecoder {
  @override
  List<int> decode(List<int> data) => lzma.decode(data);
}
