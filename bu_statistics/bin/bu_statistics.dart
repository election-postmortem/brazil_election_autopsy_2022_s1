import 'dart:io';

import 'package:bu_statistics/bu_statistics.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('USAGE:\n');
    print(
        '  \$> bu_statistics.dart path/to/bu-files/%uf_dir path/to/csv/output_dir\n');
    exit(0);
  }

  args = args.toList();

  var commaAsDecimalDelimiter =
      args.any((a) => a.toLowerCase() == 'commadecimal');

  if (commaAsDecimalDelimiter) {
    args.removeWhere((a) => a.toLowerCase() == 'commadecimal');
  }

  var busSourcePath = args[0];
  var outputDirectoryPath = args.length > 1 ? args[1] : null;

  var busSource = File(busSourcePath);
  var sourceType = busSource.statSync().type;

  Directory? busDirectory;
  File? busCompressedFile;

  if (sourceType == FileSystemEntityType.directory) {
    busDirectory = Directory(busSourcePath);
  } else if (sourceType == FileSystemEntityType.file) {
    busCompressedFile = File(busSourcePath);
  }

  var outputDirectory =
      outputDirectoryPath != null ? Directory(outputDirectoryPath) : null;

  var buStatistics = BUStatistics(
      busDirectory: busDirectory,
      busCompressedFile: busCompressedFile,
      outputDirectory: outputDirectory,
      commaAsDecimalDelimiter: commaAsDecimalDelimiter);

  print("====================================================================");
  print('$buStatistics\n');

  await buStatistics.process();
}
