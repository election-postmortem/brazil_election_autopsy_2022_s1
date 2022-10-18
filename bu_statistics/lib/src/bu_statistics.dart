import 'dart:io';

import 'package:bu_statistics/bu_statistics.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as pack_path;
import 'bu_utils.dart' as bu_utils;

/// BU files statistics.
class BUStatistics {
  static final List<BUMetric> defaultMetrics = <BUMetric>[
    BUMetric.byCloseDate(Duration(seconds: 30), sideMetrics: [
      BUMetric.byPresidentOfficeAbstentionRatio(0.01),
    ]),
    BUMetric.byEmissionDate(Duration(seconds: 30), sideMetrics: [
      BUMetric.byPresidentOfficeAbstentionRatio(0.01),
    ]),
    BUMetric.byGenerationDate(Duration(seconds: 30), sideMetrics: [
      BUMetric.byPresidentOfficeAbstentionRatio(0.01),
    ]),
    BUMetric.byGenerationDate(Duration(seconds: 30), sideMetrics: [
      BUMetric.byPresidentOfficeAbstentionRatio(0.01),
    ]),
    BUMetric.byOnlyPresidentOfficeVotesRatio(0.01, sideMetrics: [
      BUMetric.byVotersReleasedByCodeRatio(0.01),
      BUMetric.byPresidentOfficeAbstentionRatio(0.01),
    ]),
    BUMetric.byVotersReleasedByCodeRatio(0.01, sideMetrics: [
      BUMetric.byOnlyPresidentOfficeVotesRatio(0.01),
      BUMetric.byPresidentOfficeAbstentionRatio(0.01),
    ]),
  ];

  /// [Directory] with the ".bu.json.gz" files.
  final Directory? busDirectory;

  /// [File] with the compressed ".bu.json" files, usually one per UF.
  final File? busCompressedFile;

  Object? get busSource => busCompressedFile ?? busDirectory;

  /// The output [Directory] for the statistics (CSV files).
  final Directory outputDirectory;

  /// The type of [OfficeElection] to analyse. Default: `"presidente"`
  final List<String> offices;

  /// The metrics to generate. See [BUMetric].
  final List<BUMetric> metrics;

  /// If `true` it will use comma as decimal delimiter when generating
  /// the CSV files.
  final bool commaAsDecimalDelimiter;

  BUStatistics(
      {this.busDirectory,
      this.busCompressedFile,
      Directory? outputDirectory,
      List<BUMetric>? metrics,
      this.offices = const <String>['presidente'],
      this.commaAsDecimalDelimiter = false})
      : outputDirectory =
            outputDirectory ?? Directory('/tmp/bu-statistics-output'),
        metrics = metrics ?? defaultMetrics;

  /// Load the ".bu.json" files tree from the [busDirectory] or [busCompressedFile].
  Future<List<BUInfo>> loadBUs() async {
    var busSource = this.busSource;

    var loadInitTime = DateTime.now();

    List<BUInfo> allBus;
    if (busSource is Directory) {
      allBus = await _loadBUsDirectory();
    } else if (busSource is File) {
      allBus = await _loadBUsCompressedFile();
    } else {
      throw StateError(
          "Can't define a BUs source. Null `busDirectory` and `busCompressedFile`");
    }

    var loadDuration = DateTime.now().difference(loadInitTime);

    print(
        '-- Loaded BUs: ${allBus.length} (in ${loadDuration.inMilliseconds} ms)');

    return allBus;
  }

  Future<List<BUInfo>> _loadBUsCompressedFile() async {
    var busCompressedFile = this.busCompressedFile!;
    print('-- BUs compressed file: ${busCompressedFile.path}');

    var buCompressor = BUCompressor();

    var allJsons = await buCompressor.decompress(busCompressedFile,
        jsonToObject: (fileName, json) {
      var pathParts = pack_path.split(fileName);
      var partsUF = pathParts
          .map((p) => p.trim())
          .where((p) => p.length == 2 && regExpUF.hasMatch(p))
          .toList();

      var uf = partsUF.lastOrNull;
      uf ??= pathParts.last.split('-')[0];

      var buInfo = BUInfo.fromJson(uf.toLowerCase(), json);
      return buInfo;
    });

    var allBUs = allJsons.map((e) => e[1] as BUInfo).toList();

    return allBUs;
  }

  Future<List<BUInfo>> _loadBUsDirectory() async {
    var busDirectory = this.busDirectory!;
    print('-- BUs directory: ${busDirectory.path}');

    print('-- Listing ".bu.json.gz" files...');
    var filesJsonGz = busDirectory.listFilesBUJsonGz();

    print('-- Loading ${filesJsonGz.length} BUs...');
    var allBus = await filesJsonGz.loadBUs();
    return allBus;
  }

  /// Processes the [busDirectory].
  Future<void> process() async {
    print('** Processing...');
    outputDirectory.createSync(recursive: true);

    var allBUs = await loadBUs();

    var ufs = allBUs.map((e) => e.uf).toSet();

    for (var i = 0; i < metrics.length; ++i) {
      var buMetric = metrics[i];
      await _processMetric(allBUs, buMetric, ufs);
    }

    _validateBUs(allBUs);

    _saveBUsInfo(allBUs);

    showTopWinners(allBUs);
  }

  void _validateBUs(List<BUInfo> allBUs) {
    allBUs.sortByCloseDate();

    var validationsErrors = allBUs.validateAll(offices: offices);

    if (validationsErrors.isNotEmpty) {
      print(
          '\n*** Found BUs with validation errors: ${validationsErrors.length} / ${allBUs.length}');

      var file = File(
          pack_path.join(outputDirectory.path, 'bus-validation-errors.txt'));

      validationsErrors.saveValidationErrors(file);
    }
  }

  void _saveBUsInfo(List<BUInfo> allBUs) {
    var file = File(pack_path.join(outputDirectory.path, 'bus.csv'));

    allBUs.saveBUsInfo(file, offices: offices);
  }

  Future<void> _processMetric(
      List<BUInfo> allBUs, BUMetric buMetric, Set<String> ufs) async {
    var data = _compute(allBUs, buMetric: buMetric);

    var ufsLine = ufs.join('-');

    var csvFileNamePrefix = 'bu-statistics--$ufsLine--${buMetric.name}';

    {
      var file =
          File(pack_path.join(outputDirectory.path, '$csvFileNamePrefix.csv'));

      data.saveToCSV(file,
          commaAsDecimalDelimiter: false,
          dataCutTotalRatioMin: buMetric.dataCutTotalRatioMin,
          dataCutTotalRatioMax: buMetric.dataCutTotalRatioMax);
    }

    if (commaAsDecimalDelimiter) {
      var file = File(pack_path.join(
          outputDirectory.path, '$csvFileNamePrefix--commadec.csv'));

      data.saveToCSV(file,
          commaAsDecimalDelimiter: true,
          dataCutTotalRatioMin: buMetric.dataCutTotalRatioMin,
          dataCutTotalRatioMax: buMetric.dataCutTotalRatioMax);
    }
  }

  BUStatisticsData _compute<M, W>(List<BUInfo> allBUs,
      {BUMetric? buMetric, int topWinners = 2}) {
    buMetric ??= BUMetric.byGenerationDate(Duration(minutes: 5));

    var sideMetrics = buMetric.sideMetrics;

    print('\n** Computing: $buMetric');
    print('-- Side metrics: ${sideMetrics.map((e) => e.name).toList()}');

    var busByWindow = buMetric.splitBUsByWindow(allBUs);

    var metricName = buMetric.name;

    var allData = <Map<String, dynamic>>[];

    var total = 0;

    for (var busBlock in busByWindow) {
      var metric = buMetric.getMetric(busBlock.first);
      metric = buMetric.metricInWindow(metric);

      var data = _getTopWinnersVotes(busBlock,
          topWinners: topWinners, orderByCandidateID: true);

      var votersReleasedByCode =
          busBlock.map((e) => e.votersReleasedByCodeCount).sum;
      var votersBiometric = busBlock.map((e) => e.votersBiometricCount).sum;
      var votersWithoutBiometrics =
          busBlock.map((e) => e.votersWithoutBiometricsCount).sum;
      var votersInTransit = busBlock.map((e) => e.votersInTransit).sum;

      for (var i = 0; i < data.length; ++i) {
        var o = data[i];

        var votesAll = o['votes:*'] as int;
        total += votesAll;

        var metricValue = buMetric.metricToValue(metric, busBlock);

        var entry = <String, dynamic>{
          metricName: metricValue,
          ...o,
        };

        for (var sideMetric in sideMetrics) {
          var sideMetricValues = sideMetric.getMetricValues(busBlock);
          var sideMetricAverage = sideMetric.getMetricAverage(sideMetricValues);

          entry[sideMetric.name] = sideMetricAverage;

          if (sideMetricValues is List<num>) {
            entry['${sideMetric.name}.stdv'] =
                sideMetricValues.standardDeviation;
          }
        }

        entry['votersByCode'] = votersReleasedByCode;
        entry['votersBiometric'] = votersBiometric;
        entry['votersWithoutBiometrics'] = votersWithoutBiometrics;
        entry['votersInTransit'] = votersInTransit;

        entry['votersByCode.mean'] = votersReleasedByCode / busBlock.length;
        entry['votersBiometric.mean'] = votersBiometric / busBlock.length;
        entry['votersWithoutBiometrics.mean'] =
            votersWithoutBiometrics / busBlock.length;
        entry['votersInTransit.mean'] = votersInTransit / busBlock.length;

        entry['total'] = total;

        data[i] = entry;
      }

      allData.addAll(data);
    }

    return BUStatisticsData(total, allData);
  }

  List<Map<String, dynamic>> _getTopWinnersVotes(List<BUInfo> bus,
      {int topWinners = 2, bool orderByCandidateID = false}) {
    var allElectionsResultsByOffice = _selectElectionsResultsByOffice(bus);

    var officeElectionsMerge =
        _mergeOfficeElections(allElectionsResultsByOffice);

    var allData = <Map<String, dynamic>>[];

    for (var o in officeElectionsMerge) {
      var votesData = _computeVotes(o,
          topWinners: topWinners, orderByCandidateID: orderByCandidateID);

      allData.add(votesData);
    }

    return allData;
  }

  Map<String, dynamic> _computeVotes(OfficeElection officeElection,
      {int? topWinners, bool orderByCandidateID = false}) {
    var candidatesVotes = officeElection.candidatesVotes.toList();
    candidatesVotes.sort();

    var maxBus = candidatesVotes.map((e) => e.bus).max;

    var totalVotesValid = candidatesVotes.totalVotesValid;

    var candidatesSel = topWinners != null
        ? candidatesVotes.topWinners(topWinners, copyOnSort: false)
        : candidatesVotes;

    if (orderByCandidateID) {
      candidatesSel.sort((a, b) => b.id.compareTo(a.id));
    }

    var data = <Map<String, dynamic>>[];

    for (var candidateVotes in candidatesSel) {
      var ratio = candidateVotes.votes / totalVotesValid;

      var votesMean = candidateVotes.votesMean;
      var votesStandardDeviation = candidateVotes.votesStandardDeviation;

      data.add({
        'id': candidateVotes.id,
        'votes': candidateVotes.votes,
        'votes.mean': votesMean,
        'votes.stdv': votesStandardDeviation,
        'bus': candidateVotes.bus,
        'ratio': ratio,
      });
    }

    var votesRatioByID = data
        .groupListsBy((e) => 'ratio:${e['id']}')
        .map((id, list) => MapEntry(id, list.first['ratio']));

    var votesByID = data
        .groupListsBy((e) => 'votes:${e['id']}')
        .map((id, list) => MapEntry(id, list.first['votes']));

    var votesMeanByID = data
        .groupListsBy((e) => 'votes.mean:${e['id']}')
        .map((id, list) => MapEntry(id, list.first['votes.mean']));

    var votesStdvByID = data
        .groupListsBy((e) => 'votes.stdv:${e['id']}')
        .map((id, list) => MapEntry(id, list.first['votes.stdv']));

    return {
      ...votesRatioByID,
      ...votesByID,
      ...votesMeanByID,
      ...votesStdvByID,
      'votes:*': totalVotesValid,
      'votes:*.mean': totalVotesValid / maxBus,
      'bus': officeElection.bus,
      'turnout': officeElection.turnout,
      'abstentions': officeElection.abstentions,
      'abstentionsRatio': officeElection.abstentionsRatio,
      'eligibleVoters': officeElection.eligibleVoters,
      'turnout.mean': officeElection.turnout / maxBus,
      'abstentions.mean': officeElection.abstentions / maxBus,
      'eligibleVoters.mean': officeElection.eligibleVoters / maxBus,
    };
  }

  List<Map<String, dynamic>> showTopWinners(List<BUInfo> bus,
      {int topWinners = 2, bool orderByCandidateID = false}) {
    var allElectionsResultsByOffice = _selectElectionsResultsByOffice(bus);

    var officeElectionsMerge =
        _mergeOfficeElections(allElectionsResultsByOffice);

    var allData = <Map<String, dynamic>>[];

    for (var o in officeElectionsMerge) {
      _showVotes(o,
          topWinners: topWinners, orderByCandidateID: orderByCandidateID);
    }

    return allData;
  }

  void _showVotes(OfficeElection officeElection,
      {int? topWinners, bool orderByCandidateID = false}) {
    var office = officeElection.office;

    print('\nOffice election: $office');

    var abstentionsRatio = officeElection.abstentionsRatio;
    print('abstentionsRatio: ${abstentionsRatio.toStringAsFixed(4)}');

    var candidatesVotes = officeElection.candidatesVotes.toList();
    candidatesVotes.sort();

    var totalVotesValid = candidatesVotes.totalVotesValid;

    var candidatesSel = topWinners != null
        ? candidatesVotes.topWinners(topWinners, copyOnSort: false)
        : candidatesVotes;

    if (orderByCandidateID) {
      candidatesSel.sort((a, b) => b.id.compareTo(a.id));
    }

    for (var candidateVotes in candidatesSel) {
      var ratio = candidateVotes.votes / totalVotesValid;

      print(
          '  $candidateVotes\t${ratio.toStringAsFixed(4)}\t(Avg. votes by BU: ${candidateVotes.votesMean.toStringAsFixed(2)})');
    }

    print('Total votes: $totalVotesValid\n');
  }

  Map<String, List<OfficeElection>> _selectElectionsResultsByOffice(
      List<BUInfo> bus) {
    var electionsResultsByOffice =
        bus.map((bu) => bu.selectElectionsResultsByOffice(offices)).toList();

    var allElectionsResultsByOffice = electionsResultsByOffice.mergeAll();
    return allElectionsResultsByOffice;
  }

  List<OfficeElection> _mergeOfficeElections(
      Map<String, List<OfficeElection>> allElectionsResultsByOffice) {
    var officeElectionMergeAll = allElectionsResultsByOffice
        .map((office, list) => MapEntry(office, list.mergeAll()))
        .values
        .toList();
    return officeElectionMergeAll;
  }

  @override
  String toString() {
    var metricsNames = metrics.map((e) => e.name).toList();
    return 'BUStatistics{directory: ${busDirectory?.path}, outputDirectory: ${outputDirectory.path}, offices: $offices, metrics: $metricsNames, commaAsDecimalDelimiter: $commaAsDecimalDelimiter}';
  }
}

/// A statistics data calculated from BU files.
class BUStatisticsData {
  final int totalVotes;

  final List<Map<String, dynamic>> data;

  final List<ValidationError<BUInfo>> validationErrors;

  BUStatisticsData(this.totalVotes, this.data,
      [List<ValidationError<BUInfo>>? validationErrors])
      : validationErrors = validationErrors ?? [];

  /// Converts this statistics to CSV format.
  String toCSV(
      {bool commaAsDecimalDelimiter = false,
      double dataCutTotalRatioMin = 0.01,
      double dataCutTotalRatioMax = 0.985}) {
    var dataKeys = data.first.keys.toList();

    for (var e in data) {
      for (var k in dataKeys) {
        e[k] ??= 0;
      }

      var total = e['total'] as int;
      e['totalRatio'] = total / totalVotes;
    }

    data.removeWhere((e) {
      var totalRatio = e['totalRatio'] as double;
      return totalRatio < dataCutTotalRatioMin ||
          totalRatio > dataCutTotalRatioMax;
    });

    var csv = data.toCSV(commaAsDecimalDelimiter: commaAsDecimalDelimiter);

    return csv;
  }

  /// Saves this statistics to a CSV file.
  int saveToCSV(File csvFile,
      {bool commaAsDecimalDelimiter = false,
      double dataCutTotalRatioMin = 0.01,
      double dataCutTotalRatioMax = 0.985}) {
    var csv = toCSV(
        commaAsDecimalDelimiter: commaAsDecimalDelimiter,
        dataCutTotalRatioMin: dataCutTotalRatioMin,
        dataCutTotalRatioMax: dataCutTotalRatioMax);
    csvFile.writeAsStringSync(csv);
    var length = csvFile.lengthSync();
    print('-- Saved CSV: ${csvFile.path} ($length bytes)');
    return length;
  }
}
