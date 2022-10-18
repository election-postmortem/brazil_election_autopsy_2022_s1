import 'dart:io';
import 'dart:math' as math;

import 'package:bu_statistics/bu_statistics.dart';
import 'package:collection/collection.dart';

import 'bu_utils.dart' as bu_utils;

/// BU file information and statistics.
class BUInfo implements Comparable<BUInfo> {
  static final String serialVersion = "1.0";

  final BUInfoVersion version;

  /// The state of the `BU` file.
  final String uf;

  /// The city of the `BU` file.
  final int city;

  /// The election zone of the `BU` file.
  final int zone;

  /// The election section of the zone of the `BU` file.
  final int section;

  /// Number of votes with biometric (fingerprint).
  final int votersBiometricCount;

  /// Number of votes released by code (biometric issue).
  final int votersReleasedByCodeCount;

  /// Open date (first vote of the Voting Machine).
  final DateTime openDate;

  /// Close date (last vote of the Voting Machine).
  final DateTime closeDate;

  /// Emission date (BU file emission by the Voting Machine).
  final DateTime emissionDate;

  /// Generation date.
  final DateTime generationDate;

  /// The election results of the election [section].
  final List<OfficeElection> electionsResults;

  BUInfo(
    this.version,
    this.uf,
    this.city,
    this.zone,
    this.section,
    this.votersBiometricCount,
    this.votersReleasedByCodeCount,
    this.openDate,
    this.closeDate,
    this.emissionDate,
    this.generationDate,
    this.electionsResults,
  ) {
    for (var e in electionsResults) {
      e.buInfo = this;
    }
  }

  factory BUInfo.fromFile(String uf, File file) =>
      BUInfo.fromJson(uf, file.readJson());

  static Future<BUInfo> fromFileAsync(String uf, File file) {
    return file.readJsonAsync().then((json) => BUInfo.fromJson(uf, json));
  }

  factory BUInfo.fromJson(String uf, Map<String, dynamic> json) {
    var identificacao =
        json['EntidadeEnvelopeGenerico']['identificacao'][1] as Map;
    var municipioZona = identificacao['municipioZona'] as Map;
    var city = municipioZona['municipio'] as int;
    var zone = municipioZona['zona'] as int;
    var section = identificacao['secao'] as int;

    var entidadeBoletimUrna = json['EntidadeBoletimUrna'] as Map;

    var emissionDate = DateTime.parse(entidadeBoletimUrna['dataHoraEmissao']);

    var generationDate =
        DateTime.parse(entidadeBoletimUrna['cabecalho']['dataGeracao']);

    var dadosSecao = entidadeBoletimUrna['dadosSecaoSA'][1] as Map;

    var openDate = DateTime.parse(dadosSecao['dataHoraAbertura']);
    var closeDate = DateTime.parse(dadosSecao['dataHoraEncerramento']);

    var voterBiometricCount =
        entidadeBoletimUrna['qtdEleitoresCompBiometrico'] as int? ?? 0;
    var voterReleasedByCodeCount =
        entidadeBoletimUrna['qtdEleitoresLibCodigo'] as int? ?? 0;

    var urna = entidadeBoletimUrna['urna'] as Map;

    var version = urna['versaoVotacao'] as String;
    var numberSeries = urna['numeroSerieFV'] as String;

    var loadDate = DateTime.parse(
        urna['correspondenciaResultado']['carga']['dataHoraCarga']);

    var buInfoVersion = BUInfoVersion(version, numberSeries, loadDate);

    var electionResultsByType =
        entidadeBoletimUrna['resultadosVotacaoPorEleicao'] as List;

    var electionsResults = electionResultsByType
        .map((e) {
          var eligibleVoters = e['qtdEleitoresAptos'] as int;
          var results = e['resultadosVotacao'] as List;

          var allEllections = results
              .map((e) {
                var turnout = e['qtdComparecimento'] as int;
                var totaisVotosCargo = e['totaisVotosCargo'] as List;

                var elections = totaisVotosCargo.map((e) {
                  var office = e['codigoCargo'][1];
                  if (office is! String) {
                    return null;
                  }

                  var candidatesVotesJson = e['votosVotaveis'] as List;

                  var oddVotes = candidatesVotesJson
                      .where((e) => e['identificacaoVotavel'] == null)
                      .toList();

                  var blankVotes = oddVotes.firstWhereOrNull((e) =>
                              e['tipoVoto'] == 'branco')?['quantidadeVotos']
                          as int? ??
                      0;

                  var nullVotes = oddVotes.firstWhereOrNull((e) =>
                              e['tipoVoto'] == 'nulo')?['quantidadeVotos']
                          as int? ??
                      0;

                  candidatesVotesJson
                      .removeWhere((e) => e['identificacaoVotavel'] == null);

                  var candidatesVotes = candidatesVotesJson.map((e) {
                    var candidateID = e['identificacaoVotavel'] as Map;
                    var id = candidateID['codigo'] as int;
                    var party = candidateID['partido'] as int;
                    var votes = e['quantidadeVotos'] as int;

                    return CandidateVotes(party, id, office, votes);
                  }).toList();

                  return OfficeElection(office, eligibleVoters, turnout,
                      blankVotes, nullVotes, candidatesVotes);
                }).toList();

                return elections;
              })
              .expand((l) => l)
              .whereNotNull()
              .toList();

          return allEllections;
        })
        .expand((l) => l)
        .toList();

    return BUInfo(
      buInfoVersion,
      uf,
      city,
      zone,
      section,
      voterBiometricCount,
      voterReleasedByCodeCount,
      openDate,
      closeDate,
      emissionDate,
      generationDate,
      electionsResults,
    );
  }

  /// Total voters in the [section].
  int get voters => turnoutMax;

  /// The ratio of [votersBiometricCount]:[voters].
  double get votersBiometricRatio {
    var voters = this.voters;
    return voters > 0 ? votersBiometricCount / voters : 0;
  }

  /// The ratio of [votersReleasedByCodeRatio] : [voters].
  double get votersReleasedByCodeRatio {
    var voters = this.voters;
    return voters > 0 ? votersReleasedByCodeCount / voters : 0;
  }

  /// Number of voters without biometrics (fingerprint).
  int get votersWithoutBiometricsCount {
    var noBiometric = turnoutMax - votersBiometricCount;
    return noBiometric;
  }

  double get votersWithoutBiometricsRatio {
    var voters = this.voters;
    return voters > 0 ? votersWithoutBiometricsCount / voters : 0;
  }

  int? _turnoutMin;

  int get turnoutMin =>
      _turnoutMin ??= electionsResults.map((e) => e.turnout).min;

  int? _turnoutMax;

  int get turnoutMax =>
      _turnoutMax ??= electionsResults.map((e) => e.turnout).max;

  int? _eligibleVotersMin;

  /// Minimum [OfficeElection.eligibleVoters].
  int get eligibleVotersMin =>
      _eligibleVotersMin ??= electionsResults.map((e) => e.eligibleVoters).min;

  int? _eligibleVotersMax;

  /// Maximum [OfficeElection.eligibleVoters].
  int get eligibleVotersMax =>
      _eligibleVotersMax ??= electionsResults.map((e) => e.eligibleVoters).max;

  /// Voter in transit.
  int get votersInTransit => eligibleVotersMax - eligibleVotersMin;

  Duration? _generationAndCloseGap;

  /// The [Duration] gap between [generationDate] and [closeDate].
  Duration get generationAndCloseGap =>
      _generationAndCloseGap ??= generationDate.difference(closeDate);

  Duration? _emissionAndCloseGap;

  /// The [Duration] gap between [emissionDate] and [closeDate].
  Duration get emissionAndCloseGap =>
      _emissionAndCloseGap ??= emissionDate.difference(closeDate);

  Duration? _generationAndEmissionGap;

  /// The [Duration] gap between [generationDate] and [emissionDate].
  Duration get generationAndEmissionGap =>
      _generationAndEmissionGap ??= generationDate.difference(emissionDate);

  Map<String, OfficeElection>? _electionsResultsByOffice;

  /// The [electionsResults] separated by [OfficeElection.office].
  Map<String, OfficeElection> get electionsResultsByOffice =>
      _electionsResultsByOffice ??= UnmodifiableMapView(electionsResults
          .groupListsBy((e) => e.office)
          .map((office, list) => MapEntry(office, list.single)));

  /// Selects the [offices] entries in [electionsResultsByOffice].
  Map<String, OfficeElection> selectElectionsResultsByOffice(
          List<String> offices) =>
      electionsResultsByOffice.entries
          .where((e) => offices.contains(e.key))
          .toMap();

  /// The [OfficeElection.abstentionsRatio] for `presidente`.
  double get presidentOfficeAbstentionRatio {
    var electionsResultsByOffice = this.electionsResultsByOffice;
    var presidentOffice = electionsResultsByOffice['presidente']!;
    return presidentOffice.abstentionsRatio;
  }

  /// The ratio of votes for `president`:[OfficeElection.turnout].
  double get presidentOfficeVotesRatio {
    var electionsResultsByOffice = this.electionsResultsByOffice;
    var presidentOffice = electionsResultsByOffice['presidente']!;
    var presidentValidVotes = presidentOffice.totalVotesValid;
    var ratio = presidentValidVotes / presidentOffice.turnout;
    return ratio;
  }

  /// The ratio of votes between `governor` and `president`.
  /// Identifies sections with votes for president without votes for governor.
  double get onlyPresidentOfficeVotesRatio {
    var electionsResultsByOffice = this.electionsResultsByOffice;
    var presidentOffice = electionsResultsByOffice['presidente']!;
    var governorOffice = electionsResultsByOffice['governador']!;
    var presidentValidVotes = presidentOffice.totalVotesValid;
    var governorValidVotes = governorOffice.totalVotesValid;
    var ratio = governorValidVotes / presidentValidVotes;
    return ratio;
  }

  ValidationError<BUInfo>? validate({List<String>? offices}) {
    ValidationError<BUInfo>? validationError;

    var voters = this.voters;

    for (var e in electionsResults) {
      if (offices != null && !offices.contains(e.office)) continue;

      if (e.turnout != voters) {
        validationError ??= ValidationError(this);

        validationError
            .addError('$e -> turnout != voters: ${e.turnout} > $voters');
      }

      if (voters > e.eligibleVoters) {
        validationError ??= ValidationError(this);

        validationError.addError(
            '$e -> eligibleVoters > voters: ${e.eligibleVoters} > $voters');
      }

      var error = e.validate();
      if (error != null) {
        validationError ??= ValidationError(this);
        validationError.addSubError(error);
      }
    }

    return validationError != null && validationError.hasErrors
        ? validationError
        : null;
  }

  @override
  String toString() {
    return 'BUInfo{uf: $uf, city: $city, zone: $zone, section: $section, votersBiometricCount: $votersBiometricCount, votersReleasedByCodeCount: $votersReleasedByCodeCount, openDate: $openDate, closeDate: $closeDate, emissionDate: $emissionDate, generationDate: $generationDate, electionsResults: ${electionsResults.length}, version: "${version.version}"}';
  }

  @override
  int compareTo(BUInfo other) {
    var cmp = city.compareTo(other.city);
    if (cmp == 0) {
      cmp = zone.compareTo(other.zone);
      if (cmp == 0) {
        cmp = section.compareTo(other.section);
      }
    }
    return cmp;
  }
}

extension BUInfoExtension on List<BUInfo> {
  DateTime get openDateAverage => DateTime.fromMillisecondsSinceEpoch(
      map((e) => e.openDate.millisecondsSinceEpoch).average.toInt());

  DateTime get closeDateAverage => DateTime.fromMillisecondsSinceEpoch(
      map((e) => e.closeDate.millisecondsSinceEpoch).average.toInt());

  void sortByGenerationAndCloseGap() => sort(
      (a, b) => a.generationAndCloseGap.compareTo(b.generationAndCloseGap));

  void sortByGenerationAndEmissionGap() => sort((a, b) =>
      a.generationAndEmissionGap.compareTo(b.generationAndEmissionGap));

  void sortByEmissionAndCloseGap() =>
      sort((a, b) => a.emissionAndCloseGap.compareTo(b.emissionAndCloseGap));

  void sortByVotersReleasedByCodeRatio() => sort((a, b) =>
      a.votersReleasedByCodeRatio.compareTo(b.votersReleasedByCodeRatio));

  void sortByOpenDate() => sort((a, b) {
        var cmp = a.openDate.compareTo(b.openDate);
        if (cmp == 0) {
          cmp = a.compareTo(b);
        }
        return cmp;
      });

  void sortByCloseDate() => sort((a, b) {
        var cmp = a.closeDate.compareTo(b.closeDate);
        if (cmp == 0) {
          cmp = a.compareTo(b);
        }
        return cmp;
      });

  void sortByEmissionDate() => sort((a, b) {
        var cmp = a.emissionDate.compareTo(b.emissionDate);
        if (cmp == 0) {
          cmp = a.compareTo(b);
        }
        return cmp;
      });

  void sortByGenerationDate() => sort((a, b) {
        var cmp = a.generationDate.compareTo(b.generationDate);
        if (cmp == 0) {
          cmp = a.compareTo(b);
        }
        return cmp;
      });

  List<ValidationError<BUInfo>> validateAll({List<String>? offices}) =>
      map((e) => e.validate(offices: offices)).whereNotNull().toList();

  void saveBUsInfo(File busLogFile, {List<String>? offices}) {
    sortByCloseDate();

    var busLog = <Map<String, dynamic>>[];

    for (var bu in this) {
      var electionsResultsByOffice =
          bu.selectElectionsResultsByOffice(offices ?? bu_utils.offices);

      var entry = <String, dynamic>{
        'uf': bu.uf,
        'city': bu.city,
        'zone': bu.zone,
        'section': bu.section,
        'voters': bu.voters,
        'eligibleVoters': bu.eligibleVotersMax,
        'turnout': bu.turnoutMax,
        'votersInTransit': bu.votersInTransit,
        'votersBiometricCount': bu.votersBiometricCount,
        'votersReleasedByCodeCount': bu.votersReleasedByCodeCount,
        'votersWithoutBiometricsCount': bu.votersWithoutBiometricsCount,
        'openDate': bu.openDate.toHHMMSS(),
        'closeDate': bu.closeDate.toHHMMSS(),
        'loadDate': bu.version.loadDate.toYYYYDDMM_HHMM(),
      };

      for (var e in electionsResultsByOffice.values) {
        var office = e.office;

        entry['abstentions.$office'] = e.abstentions;
        entry['blankVotes.$office'] = e.blankVotes;
        entry['nullVotes.$office'] = e.nullVotes;

        for (var c in e.candidatesVotes) {
          entry['votes.$office:${c.id}'] = c.votes;
        }
      }

      busLog.add(entry);
    }

    var csv = busLog.toCSV();

    busLogFile.writeAsStringSync(csv);

    print(
        '-- Saved BUs infos: ${busLogFile.path} (${busLogFile.lengthSync()} bytes)');
  }
}

/// A metric to analise [BUInfo] instances.
class BUMetric<M, W> {
  /// The metric name.
  final String name;

  final W window;
  final M Function(BUInfo buInfo) _metricGetter;
  final M Function(List<M> metrics) _metricAverage;
  final M Function(M metric, W window) _metricInWindow;
  final M Function(M metric, W window) _metricIncrement;
  final int Function(M a, M b) _metricComparator;
  final Object Function(M metric, List<BUInfo> block) _metricToValue;
  final bool reversed;
  final double dataCutTotalRatioMin;
  final double dataCutTotalRatioMax;

  final List<BUMetric> sideMetrics;

  BUMetric(
      this.name,
      this.window,
      this._metricGetter,
      this._metricAverage,
      this._metricInWindow,
      this._metricIncrement,
      this._metricComparator,
      this._metricToValue,
      {this.reversed = false,
      this.dataCutTotalRatioMin = 0.01,
      this.dataCutTotalRatioMax = 0.985,
      List<BUMetric>? sideMetrics})
      : sideMetrics = sideMetrics ?? <BUMetric>[];

  static BUMetric<DateTime, Duration> byGenerationDate(Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDateTime('generationDate', window, (bu) => bu.generationDate,
          dataCutTotalRatioMax: 0.85, sideMetrics: sideMetrics);

  static BUMetric<DateTime, Duration> byEmissionDate(Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDateTime('emissionDate', window, (bu) => bu.emissionDate,
          dataCutTotalRatioMax: 0.85, sideMetrics: sideMetrics);

  static BUMetric<DateTime, Duration> byCloseDate(Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDateTime('closeDate', window, (bu) => bu.closeDate,
          dataCutTotalRatioMax: 0.85, sideMetrics: sideMetrics);

  static BUMetric<DateTime, Duration> byLoadDate(Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDateTime('loadDate', window, (bu) => bu.version.loadDate,
          metricToValue: (m, blk) => m.toYYYYDDMM_HHMM(),
          sideMetrics: sideMetrics);

  static BUMetric<DateTime, Duration> byDateTime(String name, Duration window,
          DateTime Function(BUInfo buInfo) metricGetter,
          {Object Function(DateTime metric, List<BUInfo> block)? metricToValue,
          bool reversed = false,
          double dataCutTotalRatioMin = 0.0,
          double dataCutTotalRatioMax = 0.985,
          List<BUMetric>? sideMetrics}) =>
      BUMetric<DateTime, Duration>(
        name,
        window,
        metricGetter,
        (l) => DateTime.fromMillisecondsSinceEpoch(
            l.map((e) => e.millisecondsSinceEpoch).average.toInt()),
        (m, w) => m.withWindow(w),
        (m, w) => m.add(w),
        (a, b) => a.compareTo(b),
        metricToValue ?? (m, blk) => m.toHHMMSS(),
        reversed: reversed,
        dataCutTotalRatioMin: dataCutTotalRatioMin,
        dataCutTotalRatioMax: dataCutTotalRatioMax,
        sideMetrics: sideMetrics,
      );

  static BUMetric<Duration, Duration> byEmissionAndCloseGap(Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDuration(
          'emissionAndCloseGap', window, (bu) => bu.emissionAndCloseGap,
          sideMetrics: sideMetrics);

  static BUMetric<Duration, Duration> byGenerationAndEmissionGap(
          Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDuration('generationAndEmissionGap', window,
          (bu) => bu.generationAndEmissionGap,
          sideMetrics: sideMetrics);

  static BUMetric<Duration, Duration> byGenerationAndCloseGap(Duration window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byDuration(
          'generationAndCloseGap', window, (bu) => bu.generationAndCloseGap,
          sideMetrics: sideMetrics);

  static BUMetric<Duration, Duration> byDuration(String name, Duration window,
          Duration Function(BUInfo buInfo) metricGetter,
          {bool reversed = false,
          double dataCutTotalRatioMin = 0.0,
          double dataCutTotalRatioMax = 0.985,
          List<BUMetric>? sideMetrics}) =>
      BUMetric<Duration, Duration>(
        name,
        window,
        metricGetter,
        (l) => Duration(
            milliseconds: l.map((e) => e.inMilliseconds).average.toInt()),
        (m, w) {
          var wMs = w.inMilliseconds;
          return Duration(milliseconds: (m.inMilliseconds ~/ wMs) * wMs);
        },
        (m, w) => m + w,
        (a, b) => a.compareTo(b),
        (m, blk) => m.inSeconds,
        reversed: reversed,
        dataCutTotalRatioMin: dataCutTotalRatioMin,
        dataCutTotalRatioMax: dataCutTotalRatioMax,
        sideMetrics: sideMetrics,
      );

  static BUMetric<num, num> byPresidentOfficeAbstentionRatio(num window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byNum('presidentAbstentionRatio', window,
          (bu) => bu.presidentOfficeAbstentionRatio,
          reversed: true, sideMetrics: sideMetrics);

  static BUMetric<num, num> byPresidentOfficeVotesRatio(num window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byNum('presidentOfficeVotesRatio', window,
          (bu) => bu.presidentOfficeVotesRatio,
          reversed: true, sideMetrics: sideMetrics);

  static BUMetric<num, num> byOnlyPresidentOfficeVotesRatio(num window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byNum('onlyPresidentVotesRatio', window,
          (bu) => bu.onlyPresidentOfficeVotesRatio,
          reversed: true,
          dataCutTotalRatioMin: 0.0,
          dataCutTotalRatioMax: 0.985,
          sideMetrics: sideMetrics);

  static BUMetric<num, num> byVotersReleasedByCodeRatio(num window,
          {List<BUMetric>? sideMetrics}) =>
      BUMetric.byNum('votersReleasedByCodeRatio', window,
          (bu) => bu.votersReleasedByCodeRatio,
          sideMetrics: sideMetrics);

  static BUMetric<num, num> byNum(
          String name, num window, num Function(BUInfo buInfo) metricGetter,
          {bool reversed = false,
          double dataCutTotalRatioMin = 0.0,
          double dataCutTotalRatioMax = 0.985,
          List<BUMetric>? sideMetrics}) =>
      BUMetric<num, num>(
        name,
        window,
        metricGetter,
        (l) => l.average,
        (m, w) => ((m ~/ w) * w),
        (m, w) => m + w,
        (a, b) => a.compareTo(b),
        (m, blk) {
          var mLast = metricGetter(blk.last);
          var mS = m.toStrFixed(2);
          var mLastS = mLast.toStrFixed(2);
          if (mS == mLastS) {
            mS = m.toStrFixed(4);
            mLastS = mLast.toStrFixed(4);
          }
          return '$mS .. $mLastS';
        },
        reversed: reversed,
        dataCutTotalRatioMin: dataCutTotalRatioMin,
        dataCutTotalRatioMax: dataCutTotalRatioMax,
        sideMetrics: sideMetrics,
      );

  void sortByMetric(List<BUInfo> bus) {
    bus.sort((a, b) {
      var m1 = _metricGetter(a);
      var m2 = _metricGetter(b);
      return _metricComparator(m1, m2);
    });
  }

  void sortReversed(List<BUInfo> bus) {
    bus.sort((a, b) {
      var m1 = _metricGetter(a);
      var m2 = _metricGetter(b);
      return _metricComparator(m2, m1);
    });
  }

  M getMetric(BUInfo bu) => _metricGetter(bu);

  List<M> getMetricValues(List<BUInfo> bus) => bus.map(getMetric).toList();

  M getMetricAverage(List<M> metrics) => _metricAverage(metrics);

  M metricInWindow(M metric) => _metricInWindow(metric, window);

  M metricIncrement(M metric, [W? window]) =>
      _metricIncrement(metric, window ?? this.window);

  int compareMetrics(M a, M b) => _metricComparator(a, b);

  Object metricToValue(M metric, List<BUInfo> block) =>
      _metricToValue(metric, block);

  List<List<BUInfo>> splitBUsByWindow(List<BUInfo> bus) {
    sortByMetric(bus);

    var cursor = getMetric(bus.first);
    cursor = metricInWindow(cursor);
    cursor = metricIncrement(cursor);

    var busByWindow = bus.splitBefore((e) {
      var metric = getMetric(e);

      if (compareMetrics(metric, cursor) >= 0) {
        do {
          cursor = metricIncrement(cursor, window!);
        } while (compareMetrics(metric, cursor) >= 0);

        return true;
      } else {
        return false;
      }
    }).toList();

    if (reversed) {
      busByWindow =
          busByWindow.reversed.map((e) => e.reversed.toList()).toList();
    }

    return busByWindow;
  }

  @override
  String toString() {
    return 'BUMetric[$name]{window: $window, reversed: $reversed, M: $M, W: $W}';
  }
}

/// Information of an election for an office.
class OfficeElection {
  /// The options [BUInfo] that contains this [OfficeElection].
  /// Merged [OfficeElection] won't have a [BUInfo] instance.
  BUInfo? buInfo;

  /// The office name.
  final String office;

  /// Number of eligible voters.
  final int eligibleVoters;

  /// The poll turnout.
  final int turnout;

  /// Number of "blank" votes. A blank vote is a vote using
  /// the "blank" button of the Voting Machine.
  /// Represents that the person will not vote for any of the candidates.
  ///
  /// See [nullVotes].
  final int blankVotes;

  /// Number of "null" votes. A "null" vote is a vote using an
  /// invalid candidate number.
  ///
  /// See [blankVotes].
  final int nullVotes;

  /// The votes for each candidate.
  final List<CandidateVotes> candidatesVotes;

  OfficeElection(this.office, this.eligibleVoters, this.turnout,
      this.blankVotes, this.nullVotes, this.candidatesVotes,
      {this.buInfo});

  int? _bus;

  int get bus => _bus ??= candidatesVotes.map((e) => e.bus).max.toInt();

  int? _totalVotesValid;

  int get totalVotesValid =>
      _totalVotesValid ??= candidatesVotes.totalVotesValid;

  int get totalVotes => totalVotesValid + blankVotes + nullVotes;

  int get abstentions => eligibleVoters - turnout;

  double get turnoutRatio => turnout / eligibleVoters;

  double get abstentionsRatio => abstentions / eligibleVoters;

  bool isSameOffice(OfficeElection other) {
    return office == other.office;
  }

  ValidationError<OfficeElection>? validate() {
    ValidationError<OfficeElection>? validationError;

    var totalVotes = this.totalVotes;

    if (totalVotes > turnout) {
      validationError ??= ValidationError(this);
      validationError.addError("totalVotes > turnout: $totalVotes > $turnout");
    }

    if (totalVotes > eligibleVoters) {
      validationError ??= ValidationError(this);
      validationError.addError(
          "totalVotes > eligibleVoters: $totalVotes > $eligibleVoters");
    }

    return validationError != null && validationError.hasErrors
        ? validationError
        : null;
  }

  @override
  String toString() {
    return 'OfficeElection[$office]{totalVotes: $totalVotesValid/$totalVotes/$eligibleVoters, eligibleVoters: $eligibleVoters, turnout: $turnout, abstentions: $abstentions, blankVotes: $blankVotes, nullVotes: $nullVotes, candidatesVotes: ${candidatesVotes.length}}';
  }

  OfficeElection merge(OfficeElection other) {
    if (identical(this, other)) {
      throw StateError("Can't merge same instance: $this");
    }

    if (!isSameOffice(other)) {
      throw StateError("Can't merge different office: $this != $other");
    }

    var candidatesVotesAll = [...candidatesVotes, ...other.candidatesVotes];

    var candidatesVotesMerge =
        candidatesVotesAll.mergeAllByCandidate(copyOnSort: false);

    return OfficeElection(
        office,
        eligibleVoters + other.eligibleVoters,
        turnout + other.turnout,
        blankVotes + other.blankVotes,
        nullVotes + other.nullVotes,
        candidatesVotesMerge);
  }
}

class ValidationError<T> {
  final T object;

  final List<String> errors;

  final List<ValidationError> subErrors = <ValidationError>[];

  ValidationError(this.object, [List<String>? errors])
      : errors = errors ?? <String>[];

  bool get hasErrors => errors.isNotEmpty || subErrors.isNotEmpty;

  void addError(String error) => errors.add(error);

  void addSubError(ValidationError subError) => subErrors.add(subError);

  @override
  String toString({String indent = ''}) {
    var s = StringBuffer('${indent}ValidationError @ ');
    s.write(object);
    s.write('\n');

    for (var e in errors) {
      s.write('$indent-- $e\n');
    }

    for (var e in subErrors) {
      s.write('\n');
      s.write(e.toString(indent: '  '));
    }

    return s.toString();
  }
}

extension ListValidationErrorExtension<T> on List<ValidationError<T>> {
  bool saveValidationErrors(File errorFile) {
    if (isEmpty) return false;

    var allErrors = map((e) => e.toString()).join(
        '\n=================================================================\n');

    errorFile.writeAsStringSync(allErrors);

    var lengthBytes = errorFile.lengthSync();
    print(
        '-- Saved Validation Errors: ${errorFile.path} ($lengthBytes bytes) [BUs with error: $length]');

    return true;
  }
}

extension CandidateVotesListExtension on List<CandidateVotes> {
  void sortByID() => sort((a, b) => a.id.compareTo(b.id));

  List<CandidateVotes> mergeAllByCandidate({bool copyOnSort = true}) {
    var sorted = copyOnSort ? toList() : this;
    sorted.sortByID();

    var blocksByID = sorted.splitBeforeIndexed((i, e) {
      var prev = sorted[i - 1];
      return prev.id != e.id;
    });

    var merges = blocksByID.map((l) => l.mergeAll()).toList();

    return merges;
  }

  CandidateVotes mergeAll() {
    final first = this[0];

    final length = this.length;
    if (length == 1) return first;
    if (length == 2) return first.merge(this[1]);

    //reduce((value, other) => value.merge(other));

    var votesSum = first.votes;
    var votesSquareSum = first.votesSquareSum;
    var busSum = first.bus;

    for (var i = 1; i < length; ++i) {
      var e = this[i];
      if (!e.isSameCandidate(first)) {
        throw StateError("Can't merge different candidates: $first != $e");
      }

      votesSum += e.votes;
      votesSquareSum += e.votesSquareSum;
      busSum += e.bus;
    }

    var merged = CandidateVotes(first.party, first.id, first.office, votesSum,
        votesSquareSum: votesSquareSum, bus: busSum);

    return merged;
  }

  Map<String, List<CandidateVotes>> get byCandidate =>
      groupListsBy((e) => e.officeID);

  int get totalVotesValid => map((e) => e.votes).sum;

  CandidateVotes get winner =>
      reduce((value, element) => element.votes > value.votes ? element : value);

  List<CandidateVotes> topWinners(int topLength, {bool copyOnSort = true}) {
    var sorted = copyOnSort ? toList() : this;
    sorted.sort();

    topLength = topLength.clamp(0, length);
    return sorted.sublist(0, topLength);
  }
}

extension OfficeElectionListExtension on List<OfficeElection> {
  List<BUInfo> get buInfos => map((e) => e.buInfo).whereNotNull().toList();

  OfficeElection mergeAll() {
    final first = this.first;

    final length = this.length;
    if (length == 1) return first;
    if (length == 2) return first.merge(this[1]);

    //return reduce((value, element) => value.merge(element));

    var totalEligibleVoters = first.eligibleVoters;
    var totalTurnout = first.turnout;
    var totalBlankVotes = first.blankVotes;
    var totalNullVotes = first.nullVotes;
    var candidatesVotesAll = first.candidatesVotes.toList();

    for (var i = 1; i < length; ++i) {
      var e = this[i];
      if (!e.isSameOffice(first)) {
        throw StateError("Can't merge different office: $first != $e");
      }

      totalEligibleVoters += e.eligibleVoters;
      totalTurnout += e.turnout;
      totalBlankVotes += e.blankVotes;
      totalNullVotes += e.nullVotes;
      candidatesVotesAll.addAll(e.candidatesVotes);
    }

    var candidatesVotesMerge =
        candidatesVotesAll.mergeAllByCandidate(copyOnSort: false);

    var merged = OfficeElection(first.office, totalEligibleVoters, totalTurnout,
        totalBlankVotes, totalNullVotes, candidatesVotesMerge);

    return merged;
  }
}

extension OfficeElectionListOfMapListExtension
    on List<Map<String, List<OfficeElection>>> {
  Map<String, List<OfficeElection>> mergeAll() {
    var offices = map((m) => m.keys).expand((e) => e).toSet();

    var merged = offices.map((office) {
      var list = expand((m) => m[office] ?? <OfficeElection>[]).toList();
      return MapEntry(office, list);
    }).toMap();

    return merged;
  }
}

extension OfficeElectionListOfMapExtension
    on List<Map<String, OfficeElection>> {
  Map<String, List<OfficeElection>> mergeAll() {
    var offices = map((m) => m.keys).expand((e) => e).toSet();

    var merged = offices.map((office) {
      var list = map((m) => m[office]).whereNotNull().toList();
      return MapEntry(office, list);
    }).toMap();

    return merged;
  }
}

/// A [Candidate] votes.
class CandidateVotes extends Candidate implements Comparable<CandidateVotes> {
  /// The number of votes of a [Candidate].
  final int votes;

  final BigInt? _votesSquareSum;

  /// The amount of Voting Machines of the [votes].
  final int bus;

  CandidateVotes(super.party, super.id, super.office, this.votes,
      {this.bus = 1, BigInt? votesSquareSum})
      : _votesSquareSum = votesSquareSum {
    if (bus < 1) {
      throw ArgumentError("`bus` < 1 ");
    }
  }

  /// Votes average over the [bus].
  double get votesMean => votes / bus;

  /// Square sum of BUs votes, for standard deviation calculation.
  BigInt get votesSquareSum => _votesSquareSum ?? BigInt.from(votes * votes);

  /// Votes standard deviation over the [bus].
  double get votesStandardDeviation {
    if (bus == 1) return 0.0;

    var votesSquareSum = this.votesSquareSum;

    // math.sqrt((squaresSum - (sum * (sum / length))) / length);

    var a = votes * (votes / bus);
    var b = votesSquareSum.toDouble() - a;
    var c = b / bus;
    var stdv = math.sqrt(c);

    return stdv;
  }

  /// Merges the votes `this` and [other]. Needs to be for the same cadidate.
  /// See [isSameCandidate(other)].
  CandidateVotes merge(CandidateVotes other) {
    if (identical(this, other)) {
      throw StateError("Can't merge same instance: $this");
    }

    if (!isSameCandidate(other)) {
      throw StateError("Can't merge different candidates: $this != $other");
    }

    var merged = CandidateVotes(party, id, office, votes + other.votes,
        votesSquareSum: votesSquareSum + other.votesSquareSum,
        bus: bus + other.bus);
    return merged;
  }

  @override
  String toString() {
    return 'CandidateVotes[$party/$id]{votes: $votes, BUs: $bus}';
  }

  /// Sortes by [vote] (higher to lower).
  @override
  int compareTo(CandidateVotes other) {
    return other.votes.compareTo(votes);
  }
}

/// A candidate.
class Candidate {
  /// The party number of the candidate.
  final int party;

  /// The id (code) of the candidate.
  /// It's the number used to vote in the candidate.
  final int id;

  /// The office title which the candidate is running for.
  final String office;

  Candidate(this.party, this.id, this.office);

  String? _officeID;

  /// [String] with "[office]/[id]"
  String get officeID => _officeID ??= '$office/$id';

  /// Returns `true` if [other] is for the same candidate of `this`.
  bool isSameCandidate(Candidate other) =>
      party == other.party && id == other.id && office == other.office;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Candidate &&
          runtimeType == other.runtimeType &&
          isSameCandidate(other);

  @override
  int get hashCode => party.hashCode ^ id.hashCode ^ office.hashCode;

  @override
  String toString() {
    return 'Candidate{party: $party, id: $id, office: $office}';
  }
}

/// The version of the Voting Machine.
class BUInfoVersion {
  /// System version.
  final String version;

  /// Number series of the Voting Machine.
  final String numberSeries;

  /// The load/installation date of the Voting Machine.
  final DateTime loadDate;

  BUInfoVersion(this.version, this.numberSeries, this.loadDate);

  @override
  String toString() {
    return 'BUInfoVersion{version: $version, numberSeries: $numberSeries, loadDate: $loadDate}';
  }
}
