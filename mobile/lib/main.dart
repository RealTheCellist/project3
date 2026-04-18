import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  runApp(const SumpyoApp());
}

class SumpyoApp extends StatelessWidget {
  const SumpyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const RootScreen(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

enum AnalyzeStatus { idle, loading, success, error }

enum ReportRange { days7, days14, days30, all }

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tab = 0;
  AnalyzeStatus _status = AnalyzeStatus.idle;
  AnalyzeResponse? _latest;
  String _error = '';
  bool _historyLoading = false;
  String _historyError = '';
  List<CheckinHistoryItem> _history = const [];

  final _text = TextEditingController(text: '?ㅻ뒛? 議곌툑 ?쇨낀?섍퀬 遺덉븞?댁슂.');
  final _speech = SpeechToText();
  final _recorder = AudioRecorder();
  bool _listening = false;
  bool _recording = false;
  bool _speechReady = false;
  String _sttProfile = 'balanced';
  int _sttAttempts = 0;
  int _sttFallbacks = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = '';
    });
    try {
      final items = await ApiClient().fetchCheckins(limit: 50);
      if (!mounted) return;
      setState(() {
        _history = items;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyError = 'History load failed: $e';
      });
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _status = AnalyzeStatus.error;
      _error = msg;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (e) => _setError('Speech error: ${e.errorMsg}'),
      );
      if (!_speechReady) {
        _setError('Speech unavailable');
        return;
      }
    }
    final started = await _speech.listen(
      localeId: 'ko_KR',
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          _text.text = r.recognizedWords;
          _text.selection = TextSelection.fromPosition(
            TextPosition(offset: _text.text.length),
          );
        });
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
    );
    if (!mounted) return;
    setState(() => _listening = started);
  }

  Future<void> _toggleRecordingAndUpload() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null || path.isEmpty) return _setError('No recording file');
      await _transcribeAndAnalyze(path);
      return;
    }
    if (!await _recorder.hasPermission()) {
      return _setError('Mic permission required');
    }
    final dir = await getTemporaryDirectory();
    final p = '${dir.path}/sumpyo_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
      path: p,
    );
    if (!mounted) return;
    setState(() => _recording = true);
  }

  Future<void> _transcribeAndAnalyze(String path) async {
    setState(() {
      _status = AnalyzeStatus.loading;
      _error = '';
      _sttAttempts += 1;
    });
    try {
      final stt = await ApiClient().transcribeAudio(path, profile: _sttProfile);
      if (!mounted) return;
      _text.text = stt.transcript;
      await analyze();
    } catch (e) {
      setState(() => _sttFallbacks += 1);
      _setError('STT failed: $e');
      await _toggleListening();
    }
  }

  Future<void> analyze() async {
    final t = _text.text.trim();
    if (t.isEmpty) return _setError('Text required');
    setState(() {
      _status = AnalyzeStatus.loading;
      _error = '';
    });
    try {
      final result = await ApiClient().analyzeCheckin(
        AnalyzeRequest(
          transcript: t,
          selfReportStress: 4,
          baselineDays: 10,
          trendDelta: 0.2,
        ),
      );
      if (!mounted) return;
      setState(() {
        _latest = result;
        _status = AnalyzeStatus.success;
        _tab = 1;
      });
      unawaited(_loadHistory());
    } catch (e) {
      _setError('Analyze failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(
        status: _status,
        error: _error,
        controller: _text,
        latest: _latest?.recoveryScore,
        onAnalyze: analyze,
        onToggleListening: _toggleListening,
        onToggleRecording: _toggleRecordingAndUpload,
        listening: _listening,
        recording: _recording,
        sttProfile: _sttProfile,
        onSttProfileChanged: (v) => setState(() => _sttProfile = v),
      ),
      ResultTab(
        status: _status,
        result: _latest,
        error: _error,
        onRetry: analyze,
      ),
      RoutineTab(result: _latest),
      ReportTab(
        history: _history,
        loading: _historyLoading,
        error: _historyError,
        onRefresh: _loadHistory,
        sttAttempts: _sttAttempts,
        sttFallbacks: _sttFallbacks,
      ),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) {
          setState(() => _tab = v);
          if (v == 3) unawaited(_loadHistory());
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Result',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            label: 'Routine',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            label: 'Report',
          ),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({
    required this.status,
    required this.error,
    required this.controller,
    required this.latest,
    required this.onAnalyze,
    required this.onToggleListening,
    required this.onToggleRecording,
    required this.listening,
    required this.recording,
    required this.sttProfile,
    required this.onSttProfileChanged,
    super.key,
  });
  final AnalyzeStatus status;
  final String error;
  final TextEditingController controller;
  final int? latest;
  final VoidCallback onAnalyze;
  final VoidCallback onToggleListening;
  final VoidCallback onToggleRecording;
  final bool listening;
  final bool recording;
  final String sttProfile;
  final ValueChanged<String> onSttProfileChanged;

  @override
  Widget build(BuildContext context) {
    final loading = status == AnalyzeStatus.loading;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '숨표 체크인',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('Latest recovery: ${latest ?? '--'}'),
        const SizedBox(height: 8),
        if (error.isNotEmpty)
          Text(error, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'STT text',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('STT'),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: sttProfile,
              items: const [
                DropdownMenuItem(value: 'fast', child: Text('fast')),
                DropdownMenuItem(value: 'balanced', child: Text('balanced')),
                DropdownMenuItem(value: 'accurate', child: Text('accurate')),
              ],
              onChanged: (v) {
                if (v != null) onSttProfileChanged(v);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onToggleRecording,
          icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
          label: Text(recording ? 'Stop recording' : 'Start recording'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onToggleListening,
                icon: Icon(listening ? Icons.mic_off : Icons.mic),
                label: Text(listening ? 'Stop voice' : 'Start voice'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: loading ? null : onAnalyze,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('지금 분석'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ResultTab extends StatelessWidget {
  const ResultTab({
    required this.status,
    required this.result,
    required this.error,
    required this.onRetry,
    super.key,
  });
  final AnalyzeStatus status;
  final AnalyzeResponse? result;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == AnalyzeStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == AnalyzeStatus.error && result == null) {
      return Center(
        child: FilledButton(onPressed: onRetry, child: Text('Retry: $error')),
      );
    }
    if (result == null) return const Center(child: Text('No result yet'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Recovery: ${result!.recoveryScore}',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(result!.explanation),
      ],
    );
  }
}

class RoutineTab extends StatelessWidget {
  const RoutineTab({required this.result, super.key});
  final AnalyzeResponse? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) return const Center(child: Text('No routine yet'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Recommended Routine',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...result!.recommendedRoutines.map(
          (e) => Card(child: ListTile(title: Text(e))),
        ),
      ],
    );
  }
}

class ReportTab extends StatefulWidget {
  const ReportTab({
    required this.history,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.sttAttempts,
    required this.sttFallbacks,
    super.key,
  });
  final List<CheckinHistoryItem> history;
  final bool loading;
  final String error;
  final Future<void> Function() onRefresh;
  final int sttAttempts;
  final int sttFallbacks;

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  ReportRange _range = ReportRange.days7;
  bool _summaryLoading = false;
  String _summaryError = '';
  ReportSummaryResponse? _summary;
  int? _selectedTrendIndex;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
  }

  int _days() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = '';
    });
    try {
      final s = await ApiClient().fetchReportSummary(days: _days(), limit: 300);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _summaryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryLoading = false;
        _summaryError = 'Summary load failed: $e';
      });
    }
  }

  List<CheckinHistoryItem> _filtered() {
    if (_range == ReportRange.all) return widget.history;
    final now = DateTime.now().toUtc();
    return widget.history.where((e) {
      final n = e.createdAt.contains('T')
          ? e.createdAt
          : e.createdAt.replaceFirst(' ', 'T');
      final dt = DateTime.tryParse(n) ?? DateTime.tryParse('${n}Z');
      if (dt == null) return true;
      return now.difference(dt).inDays <= _days();
    }).toList();
  }

  DateTime? _parseCreatedAt(String raw) {
    final n = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(n) ?? DateTime.tryParse('${n}Z');
  }

  List<CheckinHistoryItem> _filterInWindow({
    required List<CheckinHistoryItem> source,
    required DateTime startUtc,
    required DateTime endUtc,
  }) {
    return source.where((e) {
      final dt = _parseCreatedAt(e.createdAt);
      if (dt == null) return false;
      final u = dt.toUtc();
      return !u.isBefore(startUtc) && u.isBefore(endUtc);
    }).toList();
  }

  double _avgRecovery(List<CheckinHistoryItem> rows) {
    if (rows.isEmpty) return 0;
    return rows.map((e) => e.recoveryScore).reduce((a, b) => a + b) /
        rows.length;
  }

  double _avgRisk(List<CheckinHistoryItem> rows) {
    if (rows.isEmpty) return 0;
    return rows.map((e) => e.riskScore).reduce((a, b) => a + b) / rows.length;
  }

  List<ReportTagStat> _topTagsFromRows(
    List<CheckinHistoryItem> rows, {
    int take = 6,
  }) {
    final m = <String, int>{};
    for (final r in rows) {
      for (final t in r.tags) {
        m[t] = (m[t] ?? 0) + 1;
      }
    }
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list
        .take(take)
        .map((e) => ReportTagStat(tag: e.key, count: e.value))
        .toList();
  }

  String _csvEscape(String s) => '"${s.replaceAll('"', '""')}"';

  Future<void> _exportCsv(List<CheckinHistoryItem> rows) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final f = File('${dir.path}/sumpyo_report_$ts.csv');
      final b = StringBuffer();
      final avgRec = _summary?.avgRecoveryScore ?? _avgRecovery(rows);
      final avgRisk = _summary?.avgRiskScore ?? _avgRisk(rows);
      final tags = (_summary?.topTags ?? _topTagsFromRows(rows))
          .map((e) => '${e.tag}:${e.count}')
          .join('|');
      final trendSource = _summary != null ? '/report/summary' : 'local';
      b.writeln('# range_days,${_days()}');
      b.writeln('# avg_recovery,${avgRec.toStringAsFixed(2)}');
      b.writeln('# avg_risk,${avgRisk.toStringAsFixed(2)}');
      b.writeln('# top_tags,${_csvEscape(tags)}');
      b.writeln('# trend_source,$trendSource');
      b.writeln(
        'id,created_at,recovery_score,risk_score,confidence,hold_decision,tags,explanation',
      );
      for (final r in rows) {
        b.writeln(
          '${r.id},${_csvEscape(r.createdAt)},${r.recoveryScore},${r.riskScore},${r.confidence.toStringAsFixed(3)},${r.holdDecision ? 1 : 0},${_csvEscape(r.tags.join('|'))},${_csvEscape(r.explanation)}',
        );
      }
      await f.writeAsString(b.toString(), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV saved: ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV failed: $e')));
    }
  }

  Future<void> _exportLocalPdf(List<CheckinHistoryItem> rows) async {
    if (kIsWeb) {
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final f = File('${dir.path}/sumpyo_report_local_$ts.pdf');
      final pdf = pw.Document();
      final avgRec = _summary?.avgRecoveryScore ?? _avgRecovery(rows);
      final avgRisk = _summary?.avgRiskScore ?? _avgRisk(rows);
      final tags = (_summary?.topTags ?? _topTagsFromRows(rows))
          .map((e) => '${e.tag}:${e.count}')
          .join(', ');
      pdf.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range days: ${_days()}'),
            pw.Text('Rows: ${rows.length}'),
            pw.Text('Average recovery: ${avgRec.toStringAsFixed(2)}'),
            pw.Text('Average risk: ${avgRisk.toStringAsFixed(2)}'),
            pw.Text('Top tags: $tags'),
            pw.Text(
              _summary != null
                  ? 'Trend source: /report/summary'
                  : 'Trend source: local',
            ),
          ],
        ),
      );
      await f.writeAsBytes(await pdf.save(), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF: ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF failed: $e')));
    }
  }

  Future<void> _exportServerPdf() async {
    if (kIsWeb) return;
    try {
      final bytes = await ApiClient().fetchReportPdf(days: _days(), limit: 300);
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final f = File('${dir.path}/sumpyo_report_server_$ts.pdf');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF: ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF failed: $e')));
    }
  }

  List<double> _trendPoints(List<CheckinHistoryItem> rows) {
    if (_summary != null && _summary!.dailyRecovery.isNotEmpty) {
      return _summary!.dailyRecovery
          .map((e) => (e.avgRecoveryScore / 100).clamp(0.0, 1.0))
          .toList();
    }
    return rows
        .take(7)
        .toList()
        .reversed
        .map((e) => (e.recoveryScore / 100).clamp(0.0, 1.0))
        .toList();
  }

  List<String> _trendDates(List<CheckinHistoryItem> rows) {
    if (_summary != null && _summary!.dailyRecovery.isNotEmpty) {
      return _summary!.dailyRecovery.map((e) => e.date).toList();
    }
    return rows
        .take(7)
        .toList()
        .reversed
        .map((e) => e.createdAt.split(' ').first)
        .toList();
  }

  String _shortDate(String raw) {
    final token = raw.contains('T')
        ? raw.split('T').first
        : raw.split(' ').first;
    final parts = token.split('-');
    if (parts.length == 3) {
      return '${parts[1]}-${parts[2]}';
    }
    return token;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.history.isEmpty) {
      return const Center(child: Text('No report data'));
    }
    final rows = _filtered().isNotEmpty ? _filtered() : widget.history;
    final localAvgRecovery = _avgRecovery(rows);
    final localAvgRisk = _avgRisk(rows);
    final avgRecovery = _summary?.avgRecoveryScore ?? localAvgRecovery;
    final avgRisk = _summary?.avgRiskScore ?? localAvgRisk;
    final conf = _summary?.confidenceBuckets;
    final topTags = _summary?.topTags ?? _topTagsFromRows(rows);
    final trend = _trendPoints(rows);
    final trendDates = _trendDates(rows);
    final lowConfidenceAll = rows.where((e) => e.confidence < 0.4).toList();
    final lowConfidence = lowConfidenceAll.take(5).toList();
    final prevRows = _summary == null
        ? _filterInWindow(
            source: widget.history,
            startUtc: DateTime.now().toUtc().subtract(
              Duration(days: _days() * 2),
            ),
            endUtc: DateTime.now().toUtc().subtract(Duration(days: _days())),
          )
        : <CheckinHistoryItem>[];
    final curRec = _avgRecovery(rows);
    final prevRec =
        _summary?.previousPeriod.avgRecoveryScore ?? _avgRecovery(prevRows);
    final curRisk = _avgRisk(rows);
    final prevRisk =
        _summary?.previousPeriod.avgRiskScore ?? _avgRisk(prevRows);
    final selected =
        (_selectedTrendIndex != null &&
            _selectedTrendIndex! >= 0 &&
            _selectedTrendIndex! < trend.length)
        ? _selectedTrendIndex!
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Report',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () {
                unawaited(widget.onRefresh());
                unawaited(_loadSummary());
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (widget.error.isNotEmpty)
          Text(widget.error, style: const TextStyle(color: Colors.orange)),
        if (_summaryLoading) const Text('Summary syncing...'),
        if (_summaryError.isNotEmpty)
          Text(_summaryError, style: const TextStyle(color: Colors.orange)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('7d'),
              selected: _range == ReportRange.days7,
              onSelected: (_) {
                setState(() => _range = ReportRange.days7);
                unawaited(_loadSummary());
              },
            ),
            ChoiceChip(
              label: const Text('14d'),
              selected: _range == ReportRange.days14,
              onSelected: (_) {
                setState(() => _range = ReportRange.days14);
                unawaited(_loadSummary());
              },
            ),
            ChoiceChip(
              label: const Text('30d'),
              selected: _range == ReportRange.days30,
              onSelected: (_) {
                setState(() => _range = ReportRange.days30);
                unawaited(_loadSummary());
              },
            ),
            ChoiceChip(
              label: const Text('All'),
              selected: _range == ReportRange.all,
              onSelected: (_) {
                setState(() => _range = ReportRange.all);
                unawaited(_loadSummary());
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => unawaited(_exportCsv(rows)),
                child: const Text('CSV'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => unawaited(_exportLocalPdf(rows)),
                child: const Text('Local PDF'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => unawaited(_exportServerPdf()),
                child: const Text('Server PDF'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Average Recovery'),
            trailing: Text(avgRecovery.toStringAsFixed(1)),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Average Risk'),
            trailing: Text(avgRisk.toStringAsFixed(1)),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Period Compare (current vs previous)'),
            subtitle: Text(
              'Recovery ${curRec.toStringAsFixed(1)} vs ${prevRec.toStringAsFixed(1)}'
              ' (${(curRec - prevRec >= 0 ? '+' : '')}${(curRec - prevRec).toStringAsFixed(1)})'
              '\nRisk ${curRisk.toStringAsFixed(1)} vs ${prevRisk.toStringAsFixed(1)}'
              ' (${(curRisk - prevRisk >= 0 ? '+' : '')}${(curRisk - prevRisk).toStringAsFixed(1)})'
              '\nprevious rows: ${_summary?.previousPeriod.totalCheckins ?? prevRows.length}',
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Ops Metrics'),
            subtitle: Text(
              'low-confidence-rate: ${rows.isEmpty ? '0.0' : ((lowConfidenceAll.length / rows.length) * 100).toStringAsFixed(1)}%'
              ' '
              '\ntag coverage(top6): ${rows.isEmpty ? '0.0' : ((topTags.take(6).fold<int>(0, (acc, e) => acc + e.count) / rows.length) * 100).toStringAsFixed(1)}%'
              '\nstt fallback rate: ${widget.sttAttempts == 0 ? '0.0' : ((widget.sttFallbacks / widget.sttAttempts) * 100).toStringAsFixed(1)}% (${widget.sttFallbacks}/${widget.sttAttempts})',
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recovery Trend',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (selected != null && selected < trendDates.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'selected: ${_shortDate(trendDates[selected])} 쨌 ${(trend[selected] * 100).toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                SizedBox(
                  height: 120,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          if (trend.isEmpty) return;
                          final width = constraints.maxWidth <= 0
                              ? 1.0
                              : constraints.maxWidth;
                          final x = details.localPosition.dx.clamp(0.0, width);
                          final idx = trend.length == 1
                              ? 0
                              : ((x / width) * (trend.length - 1))
                                    .round()
                                    .clamp(0, trend.length - 1);
                          setState(() => _selectedTrendIndex = idx);
                        },
                        child: CustomPaint(
                          painter: _TrendChartPainter(
                            points: trend,
                            selectedIndex: selected,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                if (trendDates.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _shortDate(trendDates.first),
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(
                        _shortDate(trendDates[trendDates.length ~/ 2]),
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(
                        _shortDate(trendDates.last),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  _summary != null
                      ? 'source: /report/summary'
                      : 'source: local checkins',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Confidence Buckets'),
            subtitle: Text(
              'low=${conf?.low ?? '-'} medium=${conf?.medium ?? '-'} high=${conf?.high ?? '-'}',
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Low Confidence Cases (<0.40)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (lowConfidence.isEmpty) const Text('(none)'),
                ...lowConfidence.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${e.createdAt} 쨌 conf=${e.confidence.toStringAsFixed(2)} 쨌 rec=${e.recoveryScore} risk=${e.riskScore}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top Tags',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (topTags.isEmpty) const Text('(none)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topTags
                      .take(6)
                      .map(
                        (e) => ActionChip(
                          label: Text('${e.tag}: ${e.count}'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TagDrilldownScreen(tag: e.tag, rows: rows),
                              ),
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap a tag to open drill-down screen',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({required this.points, required this.selectedIndex});

  final List<double> points;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final safe = points.isEmpty ? <double>[0.0] : points;
    final path = Path();
    for (var i = 0; i < safe.length; i++) {
      final x = safe.length == 1
          ? size.width / 2
          : (size.width / (safe.length - 1)) * i;
      final y = size.height * (1 - safe[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = const Color(0xFF2F6B5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < safe.length) {
      final i = selectedIndex!;
      final x = safe.length == 1
          ? size.width / 2
          : (size.width / (safe.length - 1)) * i;
      final y = size.height * (1 - safe[i].clamp(0.0, 1.0));
      final dotFill = Paint()..color = const Color(0xFFFFFFFF);
      final dotStroke = Paint()
        ..color = const Color(0xFF2F6B5F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset(x, y), 5, dotFill);
      canvas.drawCircle(Offset(x, y), 5, dotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      !listEquals(oldDelegate.points, points) ||
      oldDelegate.selectedIndex != selectedIndex;
}

enum TagConfidenceFilter { all, low, medium, high }

enum TagSort { newest, oldest, recoveryDesc, confidenceAsc }

class TagDrilldownScreen extends StatefulWidget {
  const TagDrilldownScreen({required this.tag, required this.rows, super.key});

  final String tag;
  final List<CheckinHistoryItem> rows;

  @override
  State<TagDrilldownScreen> createState() => _TagDrilldownScreenState();
}

class _TagDrilldownScreenState extends State<TagDrilldownScreen> {
  TagConfidenceFilter _filter = TagConfidenceFilter.all;
  TagSort _sort = TagSort.newest;
  int _page = 0;
  static const int _pageSize = 8;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _parseCreatedAt(String raw) {
    final n = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(n) ?? DateTime.tryParse('${n}Z');
  }

  bool _matchConfidence(CheckinHistoryItem item) {
    switch (_filter) {
      case TagConfidenceFilter.all:
        return true;
      case TagConfidenceFilter.low:
        return item.confidence < 0.4;
      case TagConfidenceFilter.medium:
        return item.confidence >= 0.4 && item.confidence < 0.7;
      case TagConfidenceFilter.high:
        return item.confidence >= 0.7;
    }
  }

  List<CheckinHistoryItem> _filteredRows() {
    final query = _searchQuery.trim().toLowerCase();
    final rows = widget.rows
        .where((e) => e.tags.contains(widget.tag))
        .where(_matchConfidence)
        .where((e) {
          if (query.isEmpty) return true;
          return e.explanation.toLowerCase().contains(query) ||
              e.createdAt.toLowerCase().contains(query);
        })
        .toList();

    rows.sort((a, b) {
      switch (_sort) {
        case TagSort.newest:
          final ad =
              _parseCreatedAt(a.createdAt) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd =
              _parseCreatedAt(b.createdAt) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        case TagSort.oldest:
          final ad =
              _parseCreatedAt(a.createdAt) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd =
              _parseCreatedAt(b.createdAt) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        case TagSort.recoveryDesc:
          return b.recoveryScore.compareTo(a.recoveryScore);
        case TagSort.confidenceAsc:
          return a.confidence.compareTo(b.confidence);
      }
    });
    return rows;
  }

  String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _exportFilteredCsv(List<CheckinHistoryItem> rows) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final f = File('${dir.path}/sumpyo_tag_${widget.tag}_$ts.csv');
      final b = StringBuffer();
      b.writeln('# tag,${_csvEscape(widget.tag)}');
      b.writeln('# filter,$_filter');
      b.writeln('# sort,$_sort');
      b.writeln('# query,${_csvEscape(_searchQuery)}');
      b.writeln(
        'id,created_at,recovery_score,risk_score,confidence,tags,explanation',
      );
      for (final r in rows) {
        b.writeln(
          '${r.id},${_csvEscape(r.createdAt)},${r.recoveryScore},${r.riskScore},${r.confidence.toStringAsFixed(3)},${_csvEscape(r.tags.join('|'))},${_csvEscape(r.explanation)}',
        );
      }
      await f.writeAsString(b.toString(), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Filtered CSV saved: ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Filtered CSV failed: $e')));
    }
  }

  Future<void> _exportFilteredPdf(List<CheckinHistoryItem> rows) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final f = File('${dir.path}/sumpyo_tag_${widget.tag}_$ts.pdf');
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Tag Drill-down')),
            pw.Text('tag: ${widget.tag}'),
            pw.Text('filter: $_filter'),
            pw.Text('sort: $_sort'),
            pw.Text('query: $_searchQuery'),
            pw.Text('rows: ${rows.length}'),
          ],
        ),
      );
      await f.writeAsBytes(await pdf.save(), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Filtered PDF saved: ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Filtered PDF failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows();
    final totalPages = rows.isEmpty ? 1 : ((rows.length - 1) ~/ _pageSize) + 1;
    final page = _page.clamp(0, totalPages - 1);
    final start = page * _pageSize;
    final end = (start + _pageSize).clamp(0, rows.length);
    final pageRows = rows.sublist(start, end);

    return Scaffold(
      appBar: AppBar(title: Text('Tag Drill-down: ${widget.tag}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _page = 0;
              });
            },
            decoration: InputDecoration(
              labelText: 'Search in explanation/date',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _page = 0;
                        });
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('all'),
                selected: _filter == TagConfidenceFilter.all,
                onSelected: (_) => setState(() {
                  _filter = TagConfidenceFilter.all;
                  _page = 0;
                }),
              ),
              ChoiceChip(
                label: const Text('low'),
                selected: _filter == TagConfidenceFilter.low,
                onSelected: (_) => setState(() {
                  _filter = TagConfidenceFilter.low;
                  _page = 0;
                }),
              ),
              ChoiceChip(
                label: const Text('medium'),
                selected: _filter == TagConfidenceFilter.medium,
                onSelected: (_) => setState(() {
                  _filter = TagConfidenceFilter.medium;
                  _page = 0;
                }),
              ),
              ChoiceChip(
                label: const Text('high'),
                selected: _filter == TagConfidenceFilter.high,
                onSelected: (_) => setState(() {
                  _filter = TagConfidenceFilter.high;
                  _page = 0;
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TagSort>(
            initialValue: _sort,
            decoration: const InputDecoration(
              labelText: 'Sort',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: TagSort.newest, child: Text('Newest')),
              DropdownMenuItem(value: TagSort.oldest, child: Text('Oldest')),
              DropdownMenuItem(
                value: TagSort.recoveryDesc,
                child: Text('Recovery desc'),
              ),
              DropdownMenuItem(
                value: TagSort.confidenceAsc,
                child: Text('Confidence asc'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _sort = v;
                _page = 0;
              });
            },
          ),
          const SizedBox(height: 8),
          Text('Total ${rows.length} · page ${page + 1}/$totalPages'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => unawaited(_exportFilteredCsv(rows)),
                  child: const Text('Export CSV'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => unawaited(_exportFilteredPdf(rows)),
                  child: const Text('Export PDF'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty) const Text('(no matched rows)'),
          ...pageRows.map(
            (e) => Card(
              child: ListTile(
                title: Text(
                  '${e.createdAt} · rec=${e.recoveryScore} risk=${e.riskScore}',
                ),
                subtitle: Text(
                  'conf=${e.confidence.toStringAsFixed(2)} · ${e.explanation}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  child: const Text('Prev'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: page < totalPages - 1
                      ? () => setState(() => _page = page + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AnalyzeRequest {
  AnalyzeRequest({
    required this.transcript,
    required this.selfReportStress,
    required this.baselineDays,
    required this.trendDelta,
  });
  final String transcript;
  final int selfReportStress;
  final int baselineDays;
  final double trendDelta;
  Map<String, dynamic> toJson() => {
    'transcript': transcript,
    'self_report_stress': selfReportStress,
    'baseline_days': baselineDays,
    'trend_delta': trendDelta,
  };
}

class ComponentScores {
  ComponentScores({
    required this.selfReport,
    required this.textSignal,
    required this.trend,
    required this.voiceAux,
  });
  final double selfReport;
  final double textSignal;
  final double trend;
  final double voiceAux;
  factory ComponentScores.fromJson(Map<String, dynamic> json) =>
      ComponentScores(
        selfReport: (json['self_report'] as num).toDouble(),
        textSignal: (json['text_signal'] as num).toDouble(),
        trend: (json['trend'] as num).toDouble(),
        voiceAux: (json['voice_aux'] as num).toDouble(),
      );
}

class AnalyzeResponse {
  AnalyzeResponse({
    required this.recoveryScore,
    required this.riskScore,
    required this.confidence,
    required this.holdDecision,
    required this.explanation,
    required this.tags,
    required this.recommendedRoutines,
    required this.componentScores,
  });
  final int recoveryScore;
  final int riskScore;
  final double confidence;
  final bool holdDecision;
  final String explanation;
  final List<String> tags;
  final List<String> recommendedRoutines;
  final ComponentScores componentScores;
  factory AnalyzeResponse.fromJson(Map<String, dynamic> json) =>
      AnalyzeResponse(
        recoveryScore: json['recovery_score'] as int,
        riskScore: json['risk_score'] as int,
        confidence: (json['confidence'] as num).toDouble(),
        holdDecision: json['hold_decision'] as bool,
        explanation: json['explanation'] as String,
        tags: (json['tags'] as List<dynamic>).cast<String>(),
        recommendedRoutines: (json['recommended_routines'] as List<dynamic>)
            .cast<String>(),
        componentScores: ComponentScores.fromJson(
          json['component_scores'] as Map<String, dynamic>,
        ),
      );
}

class STTResponse {
  STTResponse({
    required this.transcript,
    required this.language,
    required this.provider,
  });
  final String transcript;
  final String language;
  final String provider;
  factory STTResponse.fromJson(Map<String, dynamic> json) => STTResponse(
    transcript: json['transcript'] as String,
    language: json['language'] as String,
    provider: json['provider'] as String,
  );
}

class CheckinHistoryItem {
  CheckinHistoryItem({
    required this.id,
    required this.createdAt,
    required this.recoveryScore,
    required this.riskScore,
    required this.confidence,
    required this.holdDecision,
    required this.tags,
    required this.explanation,
  });
  final int id;
  final String createdAt;
  final int recoveryScore;
  final int riskScore;
  final double confidence;
  final bool holdDecision;
  final List<String> tags;
  final String explanation;
  factory CheckinHistoryItem.fromJson(Map<String, dynamic> json) =>
      CheckinHistoryItem(
        id: json['id'] as int,
        createdAt: json['created_at'] as String,
        recoveryScore: json['recovery_score'] as int,
        riskScore: json['risk_score'] as int,
        confidence: (json['confidence'] as num).toDouble(),
        holdDecision: json['hold_decision'] as bool,
        tags: (json['tags'] as List<dynamic>).cast<String>(),
        explanation: json['explanation'] as String,
      );
}

class ReportTagStat {
  ReportTagStat({required this.tag, required this.count});
  final String tag;
  final int count;
  factory ReportTagStat.fromJson(Map<String, dynamic> json) =>
      ReportTagStat(tag: json['tag'] as String, count: json['count'] as int);
}

class ReportConfidenceBuckets {
  ReportConfidenceBuckets({
    required this.low,
    required this.medium,
    required this.high,
  });
  final int low;
  final int medium;
  final int high;
  factory ReportConfidenceBuckets.fromJson(Map<String, dynamic> json) =>
      ReportConfidenceBuckets(
        low: json['low'] as int,
        medium: json['medium'] as int,
        high: json['high'] as int,
      );
}

class DailyRecoveryPoint {
  DailyRecoveryPoint({
    required this.date,
    required this.avgRecoveryScore,
    required this.count,
  });
  final String date;
  final double avgRecoveryScore;
  final int count;
  factory DailyRecoveryPoint.fromJson(Map<String, dynamic> json) =>
      DailyRecoveryPoint(
        date: json['date'] as String,
        avgRecoveryScore: (json['avg_recovery_score'] as num).toDouble(),
        count: json['count'] as int,
      );
}

class ReportSummaryResponse {
  ReportSummaryResponse({
    required this.avgRecoveryScore,
    required this.avgRiskScore,
    required this.confidenceBuckets,
    required this.topTags,
    required this.dailyRecovery,
    required this.previousPeriod,
  });
  final double avgRecoveryScore;
  final double avgRiskScore;
  final ReportConfidenceBuckets confidenceBuckets;
  final List<ReportTagStat> topTags;
  final List<DailyRecoveryPoint> dailyRecovery;
  final ReportSummaryPeriod previousPeriod;
  factory ReportSummaryResponse.fromJson(Map<String, dynamic> json) =>
      ReportSummaryResponse(
        avgRecoveryScore: (json['avg_recovery_score'] as num).toDouble(),
        avgRiskScore: (json['avg_risk_score'] as num).toDouble(),
        confidenceBuckets: ReportConfidenceBuckets.fromJson(
          json['confidence_buckets'] as Map<String, dynamic>,
        ),
        topTags: (json['top_tags'] as List<dynamic>)
            .map((e) => ReportTagStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        dailyRecovery: (json['daily_recovery'] as List<dynamic>)
            .map((e) => DailyRecoveryPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        previousPeriod: ReportSummaryPeriod.fromJson(
          json['previous_period'] as Map<String, dynamic>,
        ),
      );
}

class ReportSummaryPeriod {
  ReportSummaryPeriod({
    required this.totalCheckins,
    required this.avgRecoveryScore,
    required this.avgRiskScore,
    required this.avgConfidence,
  });

  final int totalCheckins;
  final double avgRecoveryScore;
  final double avgRiskScore;
  final double avgConfidence;

  factory ReportSummaryPeriod.fromJson(Map<String, dynamic> json) =>
      ReportSummaryPeriod(
        totalCheckins: json['total_checkins'] as int,
        avgRecoveryScore: (json['avg_recovery_score'] as num).toDouble(),
        avgRiskScore: (json['avg_risk_score'] as num).toDouble(),
        avgConfidence: (json['avg_confidence'] as num).toDouble(),
      );
}

class ApiClient {
  String get _baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  Future<AnalyzeResponse> analyzeCheckin(AnalyzeRequest request) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl/analyze-checkin');
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode(request.toJson())));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_extractError(body) ?? 'HTTP ${res.statusCode}');
      }
      return AnalyzeResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<CheckinHistoryItem>> fetchCheckins({int limit = 20}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl/checkins?limit=$limit');
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_extractError(body) ?? 'HTTP ${res.statusCode}');
      }
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      return (parsed['items'] as List<dynamic>)
          .map((e) => CheckinHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<ReportSummaryResponse> fetchReportSummary({
    required int days,
    int limit = 200,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl/report/summary?days=$days&limit=$limit');
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_extractError(body) ?? 'HTTP ${res.statusCode}');
      }
      return ReportSummaryResponse.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> fetchReportPdf({required int days, int limit = 200}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        '$_baseUrl/report/export-pdf?days=$days&limit=$limit',
      );
      final req = await client.getUrl(uri);
      final res = await req.close();
      final bytes = await consolidateHttpClientResponseBytes(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          _extractError(utf8.decode(bytes, allowMalformed: true)) ??
              'HTTP ${res.statusCode}',
        );
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<STTResponse> transcribeAudio(
    String filePath, {
    String language = 'ko',
    String profile = 'balanced',
  }) async {
    final uri = Uri.parse('$_baseUrl/stt?language=$language&profile=$profile');
    final req = http.MultipartRequest('POST', uri);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final res = await req.send().timeout(const Duration(seconds: 45));
    final body = await res.stream.bytesToString();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_extractError(body) ?? 'HTTP ${res.statusCode}');
    }
    return STTResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  String? _extractError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        if (parsed['message'] is String) return parsed['message'] as String;
        if (parsed['detail'] is String) return parsed['detail'] as String;
        if (parsed['detail'] is Map<String, dynamic>) {
          final d = parsed['detail'] as Map<String, dynamic>;
          if (d['code'] is String && d['message'] is String) {
            return '[${d['code']}] ${d['message']}';
          }
          if (d['message'] is String) return d['message'] as String;
        }
      }
    } catch (_) {}
    return null;
  }
}
