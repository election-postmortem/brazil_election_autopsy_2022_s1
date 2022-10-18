import 'dart:io';

import 'package:bu_statistics/bu_statistics.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('USAGE:\n');
    print(
        '  \$> bu_compressor.dart compress path/to/bu-files/%uf_dir path/to/bu-dir-compressed-%uf.bzip2\n');
    print(
        '  \$> bu_compressor.dart decompress path/to/bu-dir-compressed-%uf.bzip2 path/to/bu-files/%uf_dir\n');
    exit(0);
  }

  var command = args[0].toLowerCase();

  if (command == 'compress') {
    var targetDir = Directory(args[1]);
    var outputFile = File(args[2]);

    print('** Compressing ${targetDir.path} -> ${outputFile.path}');

    var buDirectoryCompressor = BUDirectoryCompressor(targetDir);

    buDirectoryCompressor.compress(outputFile);
  } else if (command == 'decompress') {
    var inputFile = File(args[1]);
    var targetDir = Directory(args[2]);

    print('** Decompressing ${inputFile.path} -> ${targetDir.path}');

    var buDirectoryCompressor = BUDirectoryCompressor(targetDir);

    var savedFiles = await buDirectoryCompressor.decompressAndSaveFiles(inputFile);

    print('** Total saved files: ${savedFiles.length}');
  } else {
    print("** Unknown command: $command");
    exit(1);
  }
}
