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

class AppColors {
  static const bgTop = Color(0xFFF9F4E8);
  static const bgBottom = Color(0xFFECE6D8);
  static const primary = Color(0xFF2F6B5F);
  static const primaryDark = Color(0xFF1F4E44);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const warningBg = Color(0xFFFFF7ED);
  static const warningBorder = Color(0xFFFCD34D);
  static const errorBg = Color(0xFFFFF1F2);
  static const errorBorder = Color(0xFFFDA4AF);
}

class SumpyoApp extends StatelessWidget {
  const SumpyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sumpyo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const RootScreen(),
    );
  }
}

enum AnalyzeStatus { idle, loading, success, error }

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;
  AnalyzeStatus _status = AnalyzeStatus.idle;
  AnalyzeResponse? _latest;
  String _lastError = '';
  bool _historyLoading = false;
  String _historyError = '';
  List<CheckinHistoryItem> _history = const [];

  final TextEditingController _controller = TextEditingController(
    text: '오늘은 조금 불안하고 피곤해요.',
  );
  final SpeechToText _speech = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  bool _speechReady = false;
  bool _listening = false;
  bool _recording = false;
  String _sttProfile = 'balanced';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _historyLoading = true;
        _historyError = '';
      });
    }
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

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (error) => _setError('Speech error: ${error.errorMsg}'),
      );
      if (!_speechReady) {
        _setError('Speech recognition unavailable.');
        return;
      }
    }

    final started = await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _controller.text = result.recognizedWords;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      localeId: 'ko_KR',
    );

    if (!mounted) return;
    setState(() => _listening = started);
  }

  Future<void> _toggleRecordingAndUpload() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null || path.isEmpty) {
        _setError('No recording file found.');
        return;
      }
      await _transcribeAndAnalyze(path);
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _setError('Microphone permission is required.');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/sumpyo_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        bitRate: 128000,
      ),
      path: path,
    );

    if (!mounted) return;
    setState(() => _recording = true);
  }

  Future<void> _transcribeAndAnalyze(String audioPath) async {
    setState(() {
      _status = AnalyzeStatus.loading;
      _lastError = '';
    });
    try {
      final stt = await ApiClient().transcribeAudio(
        audioPath,
        language: 'ko',
        profile: _sttProfile,
      );
      if (!mounted) return;
      setState(() {
        _controller.text = stt.transcript;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      });
      await analyze();
    } catch (e) {
      _setError('STT failed: $e');
      await _toggleListening();
    }
  }

  Future<void> analyze() async {
    final transcript = _controller.text.trim();
    if (transcript.isEmpty) {
      _setError('분석할 텍스트를 입력하세요.');
      return;
    }

    setState(() {
      _status = AnalyzeStatus.loading;
      _lastError = '';
    });

    try {
      final response = await ApiClient().analyzeCheckin(
        AnalyzeRequest(
          transcript: transcript,
          selfReportStress: 4,
          baselineDays: 10,
          trendDelta: 0.2,
        ),
      );
      if (!mounted) return;
      setState(() {
        _latest = response;
        _status = AnalyzeStatus.success;
        _index = 1;
      });
      unawaited(_loadHistory(silent: true));
    } catch (e) {
      _setError('Analyze failed: $e');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _status = AnalyzeStatus.error;
      _lastError = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        status: _status,
        errorMessage: _lastError,
        controller: _controller,
        latestScore: _latest?.recoveryScore,
        onAnalyze: analyze,
        onToggleListening: _toggleListening,
        onToggleRecording: _toggleRecordingAndUpload,
        listening: _listening,
        recording: _recording,
        sttProfile: _sttProfile,
        onSttProfileChanged: (value) => setState(() => _sttProfile = value),
      ),
      ResultScreen(
        status: _status,
        result: _latest,
        errorMessage: _lastError,
        onRetry: analyze,
        onStartRoutine: () => setState(() => _index = 2),
      ),
      RoutineScreen(result: _latest),
      ReportScreen(
        history: _history,
        loading: _historyLoading,
        errorMessage: _historyError,
        onRefresh: () => _loadHistory(),
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, AppColors.bgBottom],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: pages[_index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) {
            setState(() => _index = value);
            if (value == 3) {
              unawaited(_loadHistory(silent: true));
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Result'),
            NavigationDestination(
              icon: Icon(Icons.self_improvement_outlined),
              label: 'Routine',
            ),
            NavigationDestination(icon: Icon(Icons.show_chart_outlined), label: 'Report'),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.status,
    required this.errorMessage,
    required this.controller,
    required this.latestScore,
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
  final String errorMessage;
  final TextEditingController controller;
  final int? latestScore;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '숨표 체크인',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('최근 회복 점수: ${latestScore ?? '--'}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          if (status == AnalyzeStatus.error && errorMessage.isNotEmpty)
            _InfoBanner(message: errorMessage, tone: BannerTone.error),
          if (status == AnalyzeStatus.error && errorMessage.isNotEmpty) const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  minLines: 5,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'STT 결과가 여기에 입력됩니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('STT Profile'),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: sttProfile,
                      items: const [
                        DropdownMenuItem(value: 'fast', child: Text('fast')),
                        DropdownMenuItem(value: 'balanced', child: Text('balanced')),
                        DropdownMenuItem(value: 'accurate', child: Text('accurate')),
                      ],
                      onChanged: (value) {
                        if (value != null) onSttProfileChanged(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onToggleRecording,
                        icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
                        label: Text(recording ? '녹음 중지 & STT' : '녹음 시작 (서버 STT)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onToggleListening,
                        icon: Icon(listening ? Icons.mic_off : Icons.mic),
                        label: Text(listening ? '음성 입력 중지' : '음성 입력 시작'),
                      ),
                    ),
                    const SizedBox(width: 10),
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
            ),
          ),
        ],
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    required this.status,
    required this.result,
    required this.errorMessage,
    required this.onRetry,
    required this.onStartRoutine,
    super.key,
  });

  final AnalyzeStatus status;
  final AnalyzeResponse? result;
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onStartRoutine;

  @override
  Widget build(BuildContext context) {
    if (status == AnalyzeStatus.loading) {
      return const _CenteredState(
        icon: Icons.hourglass_top,
        title: '분석 중입니다',
        subtitle: '잠시만 기다려주세요.',
      );
    }

    if (status == AnalyzeStatus.error && result == null) {
      return _CenteredActionState(
        icon: Icons.error_outline,
        title: '분석 실패',
        subtitle: errorMessage,
        actionLabel: '다시 시도',
        onPressed: onRetry,
      );
    }

    if (result == null) {
      return const _CenteredState(
        icon: Icons.insights_outlined,
        title: '결과가 아직 없어요',
        subtitle: '홈에서 체크인을 분석해보세요.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('회복 점수: ${result!.recoveryScore}',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(result!.explanation, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              children: [
                _ScoreBar(label: 'Self report', value: result!.componentScores.selfReport, max: 50),
                _ScoreBar(label: 'Text signal', value: result!.componentScores.textSignal, max: 35),
                _ScoreBar(label: 'Trend', value: result!.componentScores.trend, max: 10),
                _ScoreBar(label: 'Voice aux', value: result!.componentScores.voiceAux, max: 5),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onStartRoutine, child: const Text('루틴 시작')),
        ],
      ),
    );
  }
}

class RoutineScreen extends StatelessWidget {
  const RoutineScreen({required this.result, super.key});

  final AnalyzeResponse? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return const _CenteredState(
        icon: Icons.self_improvement_outlined,
        title: '루틴이 아직 없어요',
        subtitle: '분석 후 추천 루틴이 표시됩니다.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text('추천 루틴', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ...result!.recommendedRoutines.map(
          (e) => _SurfaceCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Text(e, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

enum ReportRange { days7, days14, days30, all }

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    required this.history,
    required this.loading,
    required this.errorMessage,
    required this.onRefresh,
    super.key,
  });

  final List<CheckinHistoryItem> history;
  final bool loading;
  final String errorMessage;
  final Future<void> Function() onRefresh;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportRange _range = ReportRange.days7;
  bool _summaryLoading = false;
  String _summaryError = '';
  ReportSummaryResponse? _summary;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
  }

  int _currentRangeDays() {
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
      final summary = await ApiClient().fetchReportSummary(
        days: _currentRangeDays(),
        limit: 300,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  DateTime? _parseCreatedAt(String raw) {
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.tryParse('${normalized}Z');
  }

  String _formatCreatedAt(String raw) {
    final parsed = _parseCreatedAt(raw)?.toLocal();
    if (parsed == null) return raw;
    final yy = parsed.year.toString().padLeft(4, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    final dd = parsed.day.toString().padLeft(2, '0');
    final hh = parsed.hour.toString().padLeft(2, '0');
    final min = parsed.minute.toString().padLeft(2, '0');
    return '$yy-$mm-$dd $hh:$min';
  }

  List<CheckinHistoryItem> _filteredHistory() {
    final source = widget.history;
    if (_range == ReportRange.all) return source;

    final nowUtc = DateTime.now().toUtc();
    final days = _currentRangeDays();
    return source.where((item) {
      final ts = _parseCreatedAt(item.createdAt);
      if (ts == null) return true;
      return nowUtc.difference(ts).inDays <= days;
    }).toList();
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _buildCsv(List<CheckinHistoryItem> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
      'id,created_at,recovery_score,risk_score,confidence,hold_decision,tags,explanation',
    );
    for (final row in rows) {
      buffer.writeln(
        [
          row.id.toString(),
          _csvEscape(row.createdAt),
          row.recoveryScore.toString(),
          row.riskScore.toString(),
          row.confidence.toStringAsFixed(3),
          row.holdDecision ? '1' : '0',
          _csvEscape(row.tags.join('|')),
          _csvEscape(row.explanation),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  Future<void> _exportCsv(BuildContext context, List<CheckinHistoryItem> rows) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/sumpyo_report_$timestamp.csv');
      await file.writeAsString(_buildCsv(rows), flush: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV 저장 완료: ${file.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV 저장 실패: $e')),
      );
    }
  }

  Future<void> _exportLocalPdf(BuildContext context, List<CheckinHistoryItem> rows) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web file save is not supported.')),
      );
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/sumpyo_report_local_$timestamp.pdf');
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last ${_currentRangeDays()} days'),
            pw.Text('Total rows: ${rows.length}'),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['Created', 'Recovery', 'Risk', 'Confidence', 'Tags'],
              data: rows
                  .take(20)
                  .map(
                    (r) => [
                      r.createdAt,
                      r.recoveryScore.toString(),
                      r.riskScore.toString(),
                      r.confidence.toStringAsFixed(2),
                      r.tags.join('|'),
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );
      await file.writeAsBytes(await pdf.save(), flush: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Local PDF saved: ${file.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Local PDF save failed: $e')),
      );
    }
  }

  Future<void> _exportServerPdf(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web file save is not supported.')),
      );
      return;
    }
    try {
      final bytes = await ApiClient().fetchReportPdf(
        days: _currentRangeDays(),
        limit: 300,
      );
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/sumpyo_report_server_$timestamp.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server PDF saved: ${file.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server PDF save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.history.isEmpty) {
      return const _CenteredState(
        icon: Icons.hourglass_top_rounded,
        title: '리포트 불러오는 중',
        subtitle: '체크인 기록을 가져오고 있어요.',
      );
    }
    if (widget.history.isEmpty) {
      return const _CenteredState(
        icon: Icons.show_chart_outlined,
        title: '주간 리포트 준비 중',
        subtitle: '체크인 데이터가 쌓이면 리포트가 표시됩니다.',
      );
    }

    final filtered = _filteredHistory();
    final base = filtered.isNotEmpty ? filtered : widget.history;
    final avgRecovery =
        base.map((e) => e.recoveryScore).reduce((a, b) => a + b) / base.length;
    final avgRisk = base.map((e) => e.riskScore).reduce((a, b) => a + b) / base.length;
    final chartPoints = base
        .take(7)
        .toList()
        .reversed
        .map((item) => item.recoveryScore / 100)
        .toList();

    final confidenceBuckets = <String, int>{
      '낮음 (0.0~0.39)': 0,
      '중간 (0.40~0.69)': 0,
      '높음 (0.70~1.00)': 0,
    };
    final tagCount = <String, int>{};
    for (final item in base) {
      if (item.confidence < 0.4) {
        confidenceBuckets['낮음 (0.0~0.39)'] = confidenceBuckets['낮음 (0.0~0.39)']! + 1;
      } else if (item.confidence < 0.7) {
        confidenceBuckets['중간 (0.40~0.69)'] = confidenceBuckets['중간 (0.40~0.69)']! + 1;
      } else {
        confidenceBuckets['높음 (0.70~1.00)'] = confidenceBuckets['높음 (0.70~1.00)']! + 1;
      }
      for (final tag in item.tags) {
        tagCount[tag] = (tagCount[tag] ?? 0) + 1;
      }
    }
    final sortedTags = tagCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '주간 리포트',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => unawaited(widget.onRefresh()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (widget.errorMessage.isNotEmpty)
            _InfoBanner(message: widget.errorMessage, tone: BannerTone.warning),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('7일'),
                selected: _range == ReportRange.days7,
                onSelected: (_) {
                  setState(() => _range = ReportRange.days7);
                  unawaited(_loadSummary());
                },
              ),
              ChoiceChip(
                label: const Text('14일'),
                selected: _range == ReportRange.days14,
                onSelected: (_) {
                  setState(() => _range = ReportRange.days14);
                  unawaited(_loadSummary());
                },
              ),
              ChoiceChip(
                label: const Text('30일'),
                selected: _range == ReportRange.days30,
                onSelected: (_) {
                  setState(() => _range = ReportRange.days30);
                  unawaited(_loadSummary());
                },
              ),
              ChoiceChip(
                label: const Text('전체'),
                selected: _range == ReportRange.all,
                onSelected: (_) {
                  setState(() => _range = ReportRange.all);
                  unawaited(_loadSummary());
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_exportCsv(context, base)),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('CSV'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_exportLocalPdf(context, base)),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('로컬 PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_exportServerPdf(context)),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('서버 PDF'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: '최근 회복',
                  value: '${base.first.recoveryScore}',
                  accent: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  title: '최근 리스크',
                  value: '${base.first.riskScore}',
                  accent: const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: '평균 회복',
                  value: avgRecovery.toStringAsFixed(1),
                  accent: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  title: '평균 리스크',
                  value: avgRisk.toStringAsFixed(1),
                  accent: const Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('회복 점수 추세 (최대 7회)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    painter: _MiniChartPainter(points: chartPoints),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Confidence 분포', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...confidenceBuckets.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DistributionRow(
                      label: entry.key,
                      count: entry.value,
                      total: base.length,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('태그 분포 (상위 6개)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (sortedTags.isEmpty)
                  const Text('아직 태그 데이터가 없습니다.', style: TextStyle(color: AppColors.muted))
                else
                  ...sortedTags.take(6).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DistributionRow(
                        label: entry.key,
                        count: entry.value,
                        total: base.length,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('최근 체크인', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...base.take(5).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2F1EC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${item.recoveryScore}'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.explanation, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(_formatCreatedAt(item.createdAt),
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (count / total).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('$count건 (${(ratio * 100).toStringAsFixed(0)}%)'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ratio, color: color, minHeight: 8),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.accent,
  });

  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: accent),
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.label, required this.value, required this.max});

  final String label;
  final double value;
  final double max;

  @override
  Widget build(BuildContext context) {
    final ratio = (value / max).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(value.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: ratio, minHeight: 8, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({required this.points});

  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final safe = points.isEmpty ? [0.0] : points;
    final path = Path();
    for (var i = 0; i < safe.length; i++) {
      final x = safe.length == 1 ? size.width / 2 : (size.width / (safe.length - 1)) * i;
      final y = size.height * (1 - safe[i].clamp(0, 1));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) =>
      !listEquals(points, oldDelegate.points);
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.margin = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CenteredActionState extends StatelessWidget {
  const _CenteredActionState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

enum BannerTone { warning, error }

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, required this.tone});

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final isError = tone == BannerTone.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? AppColors.errorBorder : AppColors.warningBorder,
        ),
      ),
      child: Text(message),
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

  factory AnalyzeResponse.fromJson(Map<String, dynamic> json) {
    return AnalyzeResponse(
      recoveryScore: json['recovery_score'] as int,
      riskScore: json['risk_score'] as int,
      confidence: (json['confidence'] as num).toDouble(),
      holdDecision: json['hold_decision'] as bool,
      explanation: json['explanation'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      recommendedRoutines: (json['recommended_routines'] as List<dynamic>).cast<String>(),
      componentScores: ComponentScores.fromJson(json['component_scores'] as Map<String, dynamic>),
    );
  }
}

class STTResponse {
  STTResponse({required this.transcript, required this.language, required this.provider});

  final String transcript;
  final String language;
  final String provider;

  factory STTResponse.fromJson(Map<String, dynamic> json) {
    return STTResponse(
      transcript: json['transcript'] as String,
      language: json['language'] as String,
      provider: json['provider'] as String,
    );
  }
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

  factory ComponentScores.fromJson(Map<String, dynamic> json) {
    return ComponentScores(
      selfReport: (json['self_report'] as num).toDouble(),
      textSignal: (json['text_signal'] as num).toDouble(),
      trend: (json['trend'] as num).toDouble(),
      voiceAux: (json['voice_aux'] as num).toDouble(),
    );
  }
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

  factory CheckinHistoryItem.fromJson(Map<String, dynamic> json) {
    return CheckinHistoryItem(
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
        final msg = _extractError(body) ?? 'HTTP ${res.statusCode}';
        throw Exception(msg);
      }
      return AnalyzeResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } on SocketException {
      throw Exception('Cannot reach API server. Start backend at port 8000.');
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
        final msg = _extractError(body) ?? 'HTTP ${res.statusCode}';
        throw Exception(msg);
      }
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      final items = (parsed['items'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return items.map(CheckinHistoryItem.fromJson).toList();
    } on SocketException {
      throw Exception('Cannot reach API server. Start backend at port 8000.');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> fetchReportPdf({required int days, int limit = 200}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl/report/export-pdf?days=$days&limit=$limit');
      final req = await client.getUrl(uri);
      final res = await req.close();
      final bytes = await consolidateHttpClientResponseBytes(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final text = utf8.decode(bytes, allowMalformed: true);
        final msg = _extractError(text) ?? 'HTTP ${res.statusCode}';
        throw Exception(msg);
      }
      return bytes;
    } on SocketException {
      throw Exception('Cannot reach API server. Start backend at port 8000.');
    } finally {
      client.close(force: true);
    }
  }

  Future<STTResponse> transcribeAudio(
    String filePath, {
    String language = 'ko',
    String profile = 'balanced',
    int retryCount = 1,
    int timeoutSec = 45,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retryCount; attempt++) {
      try {
        final uri = Uri.parse('$_baseUrl/stt?language=$language&profile=$profile');
        final req = http.MultipartRequest('POST', uri);
        req.files.add(await http.MultipartFile.fromPath('file', filePath));
        final streamed = await req.send().timeout(Duration(seconds: timeoutSec));
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final msg = _extractError(body) ?? 'HTTP ${streamed.statusCode}';
          throw Exception(msg);
        }
        return STTResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
      } on TimeoutException {
        lastError = Exception('STT request timeout');
      } on SocketException {
        lastError = Exception('Cannot reach API server. Start backend at port 8000.');
      } catch (e) {
        lastError = e;
      }
      if (attempt < retryCount) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    throw Exception(lastError ?? 'Unknown STT error');
  }

  String? _extractError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        if (parsed['message'] is String) return parsed['message'] as String;
        if (parsed['detail'] is String) return parsed['detail'] as String;
        if (parsed['detail'] is Map<String, dynamic>) {
          final detail = parsed['detail'] as Map<String, dynamic>;
          final code = detail['code'];
          final message = detail['message'];
          if (code is String && message is String) return '[$code] $message';
          if (message is String) return message;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
