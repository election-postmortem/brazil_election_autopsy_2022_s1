import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:bu_statistics/bu_statistics.dart';
import 'package:bu_statistics/src/bu_info.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as pack_path;

/// Election office titles:
const offices = [
  // Congressman:
  'deputadoFederal',
  // State Deputy:
  'deputadoEstadual',
  // Senator:
  'senador',
  // Governor:
  'governador',
  // President:
  'presidente'
];

/// States codes in Brazil.
const ufs = [
  "AC",
  "AL",
  "AP",
  "AM",
  "BA",
  "CE",
  "DF",
  "ES",
  "GO",
  "MA",
  "MT",
  "MS",
  "MG",
  "PA",
  "PB",
  "PR",
  "PE",
  "PI",
  "RJ",
  "RN",
  "RS",
  "RO",
  "RR",
  "SC",
  "SP",
  "SE",
  "TO"
];

/// Loads a JSON file.
dynamic loadJsonFile(String filePath) {
  var file = File(filePath).absolute;
  var data = file.readAsStringSync();
  return json.decode(data);
}

extension BUFileSystemEntityExtension on FileSystemEntity {
  List<String> get pathParts => pack_path.split(path);

  String get pathPartsLast => pathParts.last;

  bool get isNumberDirectory {
    var name = pack_path.split(path).last;
    return RegExp(r'^\d+$').hasMatch(name) &&
        statSync().type == FileSystemEntityType.directory;
  }
}

final regExpUF = RegExp(r'^[a-zA-Z]{2}$');

extension BUFileExtension on File {
  Future<BUInfo> loadBUFile() {
    var pathParts = this.pathParts;

    var partsUF =
        pathParts.where((p) => p.length == 2 && regExpUF.hasMatch(p)).toList();

    var uf = partsUF.last;

    return BUInfo.fromFileAsync(uf, this);
  }

  void writeCompressed(Uint8List bytes) {
    var compressed = GZipCodec(level: 3).encode(bytes);
    writeAsBytesSync(compressed);
  }

  Future<File> writeCompressedAsync(Uint8List bytes) {
    var compressed = GZipCodec(level: 3).encode(bytes);
    return writeAsBytes(compressed);
  }

  Uint8List readCompressed() {
    var compressed = readAsBytesSync();
    var decoded = GZipCodec().decode(compressed);
    return decoded.toUint8List();
  }

  Future<Uint8List> readCompressedAsync() {
    return readAsBytes().then((compressed) {
      var decoded = GZipCodec().decode(compressed);
      return decoded.toUint8List();
    });
  }

  String readText() {
    String text;
    if (path.endsWith('.gz')) {
      var compressed = readAsBytesSync();
      var bytes = GZipCodec().decode(compressed);
      text = utf8.decode(bytes);
    } else {
      text = readAsStringSync();
    }
    return text;
  }

  Future<String> readTextAsync() {
    if (path.endsWith('.gz')) {
      return readAsBytes().then((compressed) {
        var bytes = GZipCodec().decode(compressed);
        return utf8.decode(bytes);
      });
    } else {
      return readAsString();
    }
  }

  dynamic readJson() {
    var s = readText();
    return json.decode(s);
  }

  Future<dynamic> readJsonAsync() =>
      readTextAsync().then((s) => json.decode(s));
}

extension BUDateTimeExtension on DateTime {
  String toHHMMSS() =>
      '${hour.padLeft00}:${minute.padLeft00}:${second.padLeft00}';

  String toYYYYDDMM_HHMM() =>
      '$year-${month.padLeft00}-${day.padLeft00} ${hour.padLeft00}:${minute.padLeft00}';

  bool isBeforeOrEquals(DateTime other) =>
      microsecondsSinceEpoch <= other.microsecondsSinceEpoch;

  bool isAfterOrEquals(DateTime other) =>
      microsecondsSinceEpoch >= other.microsecondsSinceEpoch;

  DateTime withWindow(Duration window) {
    var seconds = window.inSeconds;

    if (seconds < 60) {
      return withSecondWindow(seconds);
    } else {
      return withMinuteWindow(window.inMinutes);
    }
  }

  DateTime withMinuteWindow(int minuteWindow) {
    var min = (minute ~/ minuteWindow) * minuteWindow;
    return isUtc
        ? DateTime.utc(year, month, day, hour, min, 0, 0, 0)
        : DateTime(year, month, day, hour, min, 0, 0, 0);
  }

  DateTime withSecondWindow(int secondWindow) {
    var sec = (second ~/ secondWindow) * secondWindow;
    return isUtc
        ? DateTime.utc(year, month, day, hour, minute, sec, 0, 0)
        : DateTime(year, month, day, hour, minute, sec, 0, 0);
  }
}

extension BUIterableFileExtension on Iterable<File> {
  Future<List<BUInfo>> loadBUs() async {
    // Loading in blocks of 4 files:
    var blocks = splitAfterIndexed((i, e) => i % 4 == 0);

    var allBus = <BUInfo>[];

    for (var block in blocks) {
      var bus = await Future.wait(block.map((f) => f.loadBUFile()));
      allBus.addAll(bus);
    }

    return allBus;
  }
}

extension BUDirectoryExtension on Directory {
  List<File> listFilesByExtension(String extension) {
    var suffix = extension.startsWith('.') ? extension : '.$extension';

    var files = listSync(recursive: true)
        .where((f) {
          var path = f.path;
          if (!path.endsWith(suffix)) return false;
          var pathParts = pack_path.split(path);
          return !pathParts.last.startsWith('.');
        })
        .whereType<File>()
        .toList();

    return files;
  }

  List<File> listFilesBUJsonGz() => listFilesByExtension(".bu.json.gz");
}

extension BUIntExtension on int {
  String get padLeft00 => toString().padLeft(2, '0');
}

extension BUNumExtension on num {
  String toStrFixed(int fractionDigits) =>
      this is int ? toString() : toStringAsFixed(fractionDigits);
}

extension IterableMapEntryExtension<K, V> on Iterable<MapEntry<K, V>> {
  Map<K, V> toMap() => Map<K, V>.fromEntries(this);
}

extension BUListIntExtension on List<int> {
  Uint8List toUint8List() {
    var self = this;
    return self is Uint8List ? self : Uint8List.fromList(self);
  }
}

extension BUListNumExtension on List<num> {
  double get variance {
    var mean = average;

    var sumSquares = 0.0;
    for (var n in this) {
      var d = mean - n;
      sumSquares += d * d;
    }

    return sumSquares / (length - 1);
  }

  double get standardDeviation => math.sqrt(variance);
}

mixin BytesReadMixin {
  int readByte();

  Uint8List readBytes(int sz);

  int readInt16();

  int readInt32();

  int readInt64();

  double readDouble32();

  double readDouble64();

  Uint8List readBlock16() {
    var sz = readInt16();
    return readBytes(sz);
  }

  Uint8List readBlock32() {
    var sz = readInt32();
    return readBytes(sz);
  }

  String readString16() => utf8.decode(readBlock16());

  String readString32() => utf8.decode(readBlock32());

  bool readBool() => readByte() != 0;

  E readEnum<E extends Enum>(List<E> enums) {
    var idx = readByte();
    return enums[idx];
  }

  List<String> readListOfString16() {
    var length = readInt32();
    return List.generate(length, (i) => readString16());
  }

  List<String> buildStringTable(dynamic json, {int stringMaxLength = 32}) {
    var map = _collectStringMap(json, stringMaxLength: stringMaxLength);

    var keys = map.entries
        .where((e) => e.value > 1 && e.key.length > 2)
        .map((e) => e.key)
        .toList();

    keys.sort((a, b) {
      var c1 = map[a]!;
      var c2 = map[b]!;
      return c2.compareTo(c1);
    });

    while (keys.length > 256) {
      keys.removeLast();
    }

    return keys;
  }

  Map<String, int> _collectStringMap(dynamic json,
      {Map<String, int>? stringMap, int stringMaxLength = 32}) {
    stringMap ??= <String, int>{};

    if (json == null) {
      return stringMap;
    } else if (json is String) {
      if (json.length <= stringMaxLength) {
        _incrementStringMap(stringMap, json);
      }
    } else if (json is Map) {
      for (var e in json.entries) {
        _collectStringMap(e.key, stringMap: stringMap);
        _collectStringMap(e.value, stringMap: stringMap);
      }
    } else if (json is List) {
      for (var e in json) {
        _collectStringMap(e, stringMap: stringMap);
      }
    }

    return stringMap;
  }

  void _incrementStringMap(Map<String, int> stringMap, String json) {
    stringMap.update(json, (count) => count + 1, ifAbsent: () => 1);
  }

  dynamic readJson({List<String>? stringTable}) {
    var t = _readJsonType();

    switch (t) {
      case BUJsonType.typeNull:
        return null;
      case BUJsonType.typeString16:
      case BUJsonType.typeString32:
      case BUJsonType.typeStringTable:
        return readJsonString(stringTable: stringTable, t: t);
      case BUJsonType.typeInt16:
        return readInt16();
      case BUJsonType.typeInt32:
        return readInt32();
      case BUJsonType.typeBool:
        return readBool();
      case BUJsonType.typeDouble:
        return readDouble32();
      case BUJsonType.typeList:
        return readJsonList(readType: false, stringTable: stringTable);
      case BUJsonType.typeMap:
        return readJsonMap(readType: false, stringTable: stringTable);
      default:
        throw StateError("Invalid type: $t");
    }
  }

  int readJsonInt({bool readType = true}) {
    var t = _readJsonTypeChecked(BUJsonType.typeInt16, BUJsonType.typeInt32);

    switch (t) {
      case BUJsonType.typeInt16:
        return readInt16();
      case BUJsonType.typeInt32:
        return readInt32();
      default:
        throw StateError("Not a JSON int type: $t");
    }
  }

  double readJsonDouble({bool readType = true}) {
    if (readType) _readJsonTypeChecked(BUJsonType.typeDouble);
    return readDouble32();
  }

  bool readJsonBool({bool readType = true}) {
    if (readType) _readJsonTypeChecked(BUJsonType.typeBool);
    return readBool();
  }

  String readJsonString({List<String>? stringTable, BUJsonType? t}) {
    t ??= _readJsonTypeChecked(BUJsonType.typeString16, BUJsonType.typeString32,
        BUJsonType.typeStringTable);

    switch (t) {
      case BUJsonType.typeString16:
        return readString16();
      case BUJsonType.typeString32:
        return readString32();
      case BUJsonType.typeStringTable:
        {
          var idx = readByte();
          if (stringTable == null) {
            throw StateError("No stringTable! String index: $idx");
          }

          var s = stringTable[idx];
          return s;
        }
      default:
        throw StateError("Not a JSON string type: $t");
    }
  }

  List readJsonList({List<String>? stringTable, bool readType = true}) {
    if (readType) _readJsonTypeChecked(BUJsonType.typeList);

    var length = readInt32();

    var list = List.generate(length, (i) => readJson(stringTable: stringTable));
    return list;
  }

  Map<String, dynamic> readJsonMap(
      {List<String>? stringTable, bool readType = true}) {
    if (readType) _readJsonTypeChecked(BUJsonType.typeMap);

    var length = readInt32();

    var keys =
        List.generate(length, (i) => readJsonString(stringTable: stringTable))
            .toList();

    var values =
        List.generate(length, (i) => readJson(stringTable: stringTable))
            .toList();

    var map = Map.fromIterables(keys, values);
    return map;
  }

  BUJsonType _readJsonType() {
    var t = readEnum(BUJsonType.values);
    return t;
  }

  BUJsonType _readJsonTypeChecked(BUJsonType expected,
      [BUJsonType? expected2, BUJsonType? expected3]) {
    var t = readEnum(BUJsonType.values);

    var ok = t == expected || t == expected2 || t == expected3;

    if (!ok) {
      var l = [expected, expected2, expected3].whereNotNull();
      throw StateError("Expect type error: $t != ${l.join(', ')}");
    }

    return t;
  }
}

mixin BytesWriteMixin {
  void writeByte(int b);

  void writeBytes(List<int> bs);

  void writeInt16(int n);

  void writeInt32(int n);

  void writeInt64(int n);

  void writeDouble32(double d);

  void writeDouble64(double d);

  void writeBlock16(List<int> bs) {
    writeInt16(bs.length);
    writeBytes(bs);
  }

  void writeBlock32(List<int> bs) {
    writeInt32(bs.length);
    writeBytes(bs);
  }

  void writeString16(String s) => writeBlock16(utf8.encode(s));

  void writeString32(String s) => writeBlock32(utf8.encode(s));

  void writeBool(bool b) => writeByte(b ? 1 : 0);

  void writeEnum(Enum e) => writeByte(e.index);

  void writeListOfString16(List<String> l) {
    writeInt32(l.length);
    for (var s in l) {
      writeString16(s);
    }
  }

  void writeJson(dynamic json, {List<String>? stringTable}) {
    if (json == null) {
      writeEnum(BUJsonType.typeNull);
    } else if (json is String) {
      writeJsonString(json, stringTable: stringTable);
    } else if (json is int) {
      writeJsonInt(json);
    } else if (json is bool) {
      writeJsonBool(json);
    } else if (json is double) {
      writeJsonDouble(json);
    } else if (json is Map) {
      var map = json is Map<String, dynamic>
          ? json
          : json.map((k, v) => MapEntry("$k", v));
      writeJsonMap(map, stringTable: stringTable);
    } else if (json is List) {
      writeJsonList(json, stringTable: stringTable);
    }
  }

  void writeJsonInt(int n) {
    if (n < 32767 && n > -32768) {
      writeEnum(BUJsonType.typeInt16);
      writeInt16(n);
    } else {
      writeEnum(BUJsonType.typeInt32);
      writeInt32(n);
    }
  }

  void writeJsonDouble(double n) {
    writeEnum(BUJsonType.typeDouble);
    writeDouble32(n);
  }

  void writeJsonBool(bool b) {
    writeEnum(BUJsonType.typeBool);
    writeBool(b);
  }

  void writeJsonString(String s, {List<String>? stringTable}) {
    if (stringTable != null) {
      var idx = stringTable.indexOf(s);
      if (idx >= 0) {
        assert(idx < 256);
        writeEnum(BUJsonType.typeStringTable);
        writeByte(idx);
        return;
      }
    }

    var length = s.length;

    if (length < 32767 && length > -32768) {
      writeEnum(BUJsonType.typeString16);
      writeString16(s);
    } else {
      writeEnum(BUJsonType.typeString32);
      writeString32(s);
    }
  }

  void writeJsonList(List list, {List<String>? stringTable}) {
    writeEnum(BUJsonType.typeList);

    writeInt32(list.length);
    for (var e in list) {
      writeJson(e, stringTable: stringTable);
    }
  }

  void writeJsonMap(Map<String, dynamic> map, {List<String>? stringTable}) {
    writeEnum(BUJsonType.typeMap);

    writeInt32(map.length);

    var keys = map.keys.toList()..sort();

    for (var k in keys) {
      writeJsonString(k, stringTable: stringTable);
    }

    for (var k in keys) {
      var v = map[k];
      writeJson(v, stringTable: stringTable);
    }
  }
}

class Bytes with BytesReadMixin, BytesWriteMixin {
  Uint8List _buffer;

  late ByteData _bytesData;

  Bytes({int capacity = 1024}) : _buffer = Uint8List(capacity) {
    _setBytesData();
  }

  Bytes.from(this._buffer) {
    _setBytesData();
  }

  void _setBytesData() {
    _bytesData =
        _buffer.buffer.asByteData(_buffer.offsetInBytes, _buffer.lengthInBytes);
  }

  void reset() {
    _size = 0;
    _pos = 0;
  }

  int _size = 0;

  int get size => _size;

  int _pos = 0;

  int get position => _pos;

  void seek(int pos) => _pos = pos;

  void _incrementPos(int pos) {
    _pos += pos;
    if (_pos > _size) {
      _size = _pos;
    }
  }

  void ensureCapacity(int length) {
    if (_buffer.length < length) {
      const mb100 = (1024 * 1024 * 100);

      int newLength;
      if (_buffer.length < mb100) {
        newLength = _buffer.length * 2;
        while (newLength < length) {
          newLength = newLength * 2;
        }
      } else {
        newLength = _buffer.length + mb100;
        while (newLength < length) {
          newLength = newLength + mb100;
        }
      }

      var buffer2 = Uint8List(newLength);
      buffer2.setRange(0, _buffer.length, _buffer);

      _buffer = buffer2;
      _setBytesData();
    }
  }

  @override
  void writeByte(int b) {
    if (b < 0 || b > 255) throw ArgumentError("Invalid byte: $b");
    ensureCapacity(_pos + 1);
    _buffer[_pos] = b;
    _incrementPos(1);
  }

  @override
  int readByte() {
    var b = _buffer[_pos];
    _incrementPos(1);
    return b;
  }

  @override
  void writeBytes(List<int> bs) {
    var length = bs.length;
    ensureCapacity(_pos + length);
    _buffer.setRange(_pos, _pos + length, bs);
    _incrementPos(length);
  }

  @override
  Uint8List readBytes(int sz) {
    var bs = _buffer.sublist(_pos, _pos + sz);
    _incrementPos(sz);
    return bs;
  }

  @override
  void writeInt16(int n) {
    ensureCapacity(_pos + 2);
    _bytesData.setInt16(_pos, n);
    _incrementPos(2);
  }

  @override
  int readInt16() {
    var n = _bytesData.getInt16(_pos);
    _incrementPos(2);
    return n;
  }

  @override
  void writeInt32(int n) {
    ensureCapacity(_pos + 4);
    _bytesData.setInt32(_pos, n);
    _incrementPos(4);
  }

  @override
  int readInt32() {
    var n = _bytesData.getInt32(_pos);
    _incrementPos(4);
    return n;
  }

  @override
  void writeInt64(int n) {
    ensureCapacity(_pos + 8);
    _bytesData.setInt64(_pos, n);
    _incrementPos(8);
  }

  @override
  int readInt64() {
    var n = _bytesData.getInt64(_pos);
    _incrementPos(8);
    return n;
  }

  @override
  void writeDouble32(double d) {
    ensureCapacity(_pos + 4);
    _bytesData.setFloat32(_pos, d);
    _incrementPos(4);
  }

  @override
  double readDouble32() {
    var n = _bytesData.getFloat32(_pos);
    _incrementPos(4);
    return n;
  }

  @override
  void writeDouble64(double d) {
    ensureCapacity(_pos + 8);
    _bytesData.setFloat64(_pos, d);
    _incrementPos(8);
  }

  @override
  double readDouble64() {
    var n = _bytesData.getFloat64(_pos);
    _incrementPos(8);
    return n;
  }

  Uint8List toBytes() {
    if (_buffer.length == _size) {
      return _buffer;
    } else {
      var bs = Uint8List(_size);
      bs.setRange(0, _size, _buffer);
      return bs;
    }
  }
}

enum BUJsonType {
  typeStringMap,
  typeNull,
  typeBool,
  typeInt16,
  typeInt32,
  typeDouble,
  typeString16,
  typeString32,
  typeStringTable,
  typeList,
  typeMap,
}

class FileBytes with BytesReadMixin {
  final RandomAccessFile _fin;

  FileBytes(this._fin);

  FileBytes.fromFile(File file) : this(file.openSync());

  void close() => _fin.closeSync();

  @override
  int readByte() => _fin.readByteSync();

  @override
  Uint8List readBytes(int sz) => _fin.readSync(sz);

  @override
  double readDouble32() => Bytes.from(readBytes(4)).readDouble32();

  @override
  double readDouble64() => Bytes.from(readBytes(8)).readDouble64();

  @override
  int readInt16() => Bytes.from(readBytes(2)).readInt16();

  @override
  int readInt32() => Bytes.from(readBytes(4)).readInt32();

  @override
  int readInt64() => Bytes.from(readBytes(8)).readInt64();
}

Future<R> parallelCall<R, A>(R Function(A args) call, A args) async {
  var port = ReceivePort();

  Isolate.spawn((List msg) {
    final port = msg[0] as SendPort;
    var args = msg[1] as A;
    var res = call(args);
    Isolate.exit(port, res);
  }, [port.sendPort, args], onExit: port.sendPort);

  var result = await port.first;
  return result as R;
}

extension ListMapExtension on List<Map<String, dynamic>> {
  String toCSV({bool commaAsDecimalDelimiter = false}) {
    var keys = first.keys.toList();

    var csvHeader = keys.join(",");

    var csvLines = map((e) {
      var values = keys.map((k) => e[k]);

      var line = values
          .map((e) => _toCSVDecimal(e,
              commaAsDecimalDelimiter: commaAsDecimalDelimiter))
          .join(',');
      return line;
    }).toList();

    var csvAllLines = <String>[csvHeader, ...csvLines];

    var csv = csvAllLines.join('\n');
    return csv;
  }

  String _toCSVDecimal(Object? e, {bool commaAsDecimalDelimiter = false}) {
    if (e == null) return '';

    String csvValue;

    if (e is! double) {
      csvValue = '$e';
    } else {
      var d = e.toStringAsFixed(4);

      if (commaAsDecimalDelimiter) {
        var idx = d.indexOf('.');
        if (idx >= 0) {
          d = '${d.substring(0, idx)},${d.substring(idx + 1)}';
        }
      }

      csvValue = d;
    }

    if (csvValue.contains(',')) {
      csvValue = '"$csvValue"';
    }

    return csvValue;
  }
}
