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
  static const chip = Color(0xFFE2F1EC);
  static const warningBg = Color(0xFFFFF7ED);
  static const warningBorder = Color(0xFFFCD34D);
  static const errorBg = Color(0xFFFFF1F2);
  static const errorBorder = Color(0xFFFDA4AF);
}

class SumpyoApp extends StatelessWidget {
  const SumpyoApp({super.key});
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sumpyo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: Colors.transparent,
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFF8F7F2),
          indicatorColor: Color(0xFFD8EBE4),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
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
    text: '???노츓?? 嶺뚮씭?껇??筌먲퐣類????ｋ걠???브퀗????釉띾쐠????겶???????怨몃뭵.',
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
        onError: (error) {
          _setError('Speech error: ${error.errorMsg}');
        },
      );
      if (!_speechReady) {
        _setError('Speech recognition permission denied or unavailable.');
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
    if (!started) {
      _setError('Could not start voice input.');
    }
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
      _setError('Microphone permission is required for recording.');
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
      await _fallbackToLocalSpeechInput();
    }
  }

  Future<void> _fallbackToLocalSpeechInput() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '??類ㅼ뮅 STT?띠럾? ?釉띾쐠??筌먐삳┃???リ옇?쀧뵳??????筌뤾쑬六??怨쀬Ŧ ?熬곥굦???紐껊퉵?? 嶺뚮씭흮????낅슣?섋땻??',
        ),
      ),
    );
    await _toggleListening();
  }

  Future<void> analyze() async {
    final transcript = _controller.text.trim();
    if (transcript.isEmpty) {
      _setError('Please enter transcript text before analysis.');
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

  Future<void> _loadHistory({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _historyLoading = true;
        _historyError = '';
      });
    } else {
      setState(() => _historyError = '');
    }

    try {
      final items = await ApiClient().fetchCheckins(limit: 20);
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

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _status = AnalyzeStatus.error;
      _lastError = message;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
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
        onStartRoutine: () => setState(() => _index = 2),
        onRetry: analyze,
      ),
      RoutineScreen(result: _latest),
      ReportScreen(
        result: _latest,
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
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
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

  bool get _loading => status == AnalyzeStatus.loading;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '?⑦몴 泥댄겕??,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '??롳펷 3?? 筌띾뜆?????궗 ?룐뫂?????뽰삂????紐꾩뒄.',
                    style: TextStyle(fontSize: 15, color: AppColors.muted),
                  ),
                ],
              ),
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.spa_rounded, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HeroScoreCard(score: latestScore),
          const SizedBox(height: 12),
          const Text(
            '??⑤베鍮???熬곥룗????????濡?뵹 嶺뚯쉳?????熬곣뫀六???덈펲.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          if (status == AnalyzeStatus.error && errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoBanner(message: errorMessage, tone: BannerTone.error),
          ],
          const SizedBox(height: 16),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '?뚯꽦 泥댄겕???띿뒪??,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  minLines: 5,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 16, color: AppColors.text),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFFAFAF8),
                    hintText: 'STT 野껉퀗?드첎? ??由????낆젾??몃빍??',
                    hintStyle: const TextStyle(color: AppColors.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD7DCCE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD7DCCE)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'STT Profile',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: sttProfile,
                  items: const [
                    DropdownMenuItem(value: 'fast', child: Text('fast')),
                    DropdownMenuItem(
                      value: 'balanced',
                      child: Text('balanced'),
                    ),
                    DropdownMenuItem(
                      value: 'accurate',
                      child: Text('accurate'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSttProfileChanged(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onToggleRecording,
            icon: Icon(
              recording
                  ? Icons.stop_circle_outlined
                  : Icons.fiber_manual_record,
            ),
            label: Text(
              recording ? '?獄???繞벿살탳? & ??類ㅼ뮅 STT' : '?獄?????戮곗굚 (??類ㅼ뮅 STT)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: recording
                  ? const Color(0xFFB91C1C)
                  : AppColors.primaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onToggleListening,
                  icon: Icon(
                    listening ? Icons.mic_off_rounded : Icons.mic_rounded,
                  ),
                  label: Text(
                    listening ? '????????놁졑 繞벿살탳?' : '????????놁졑 ??戮곗굚',
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: Color(0xFFB9CFC8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : onAnalyze,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '吏湲?遺꾩꽍',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroScoreCard extends StatelessWidget {
  const _HeroScoreCard({required this.score});

  final int? score;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = score?.toString() ?? '--';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332F6B5F),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '???노츓 ???沅??????,
                  style: TextStyle(color: Color(0xFFE5F2EE), fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1,
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

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    required this.status,
    required this.result,
    required this.errorMessage,
    required this.onStartRoutine,
    required this.onRetry,
    super.key,
  });

  final AnalyzeStatus status;
  final AnalyzeResponse? result;
  final String errorMessage;
  final VoidCallback onStartRoutine;
  final VoidCallback onRetry;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (status == AnalyzeStatus.loading) {
      return const _CenteredState(
        icon: Icons.hourglass_top_rounded,
        title: '?釉뚯뫒??繞벿살탳????덈펲',
        subtitle: '??ル∥六사춯??リ옇?????낅슣?섋땻??',
      );
    }

    if (status == AnalyzeStatus.error && result == null) {
      return _CenteredActionState(
        icon: Icons.error_outline,
        title: '?釉뚯뫒?????덉넮',
        subtitle: errorMessage.isEmpty
            ? '???고뱺?????곕뻣 ??類ｌ┣???낅슣?섋땻??'
            : errorMessage,
        actionLabel: '???곕뻣 ??類ｌ┣',
        onPressed: onRetry,
      );
    }

    if (result == null) {
      return const _CenteredState(
        icon: Icons.insights_outlined,
        title: '野껉퀗?드첎? ?袁⑹춦 ??곷선??',
        subtitle: '???遺얇늺?癒?퐣 筌ｋ똾寃?紐꾩뱽 ?브쑴苑????紐꾩뒄.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '???沅??????,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
                Text(
                  '${result!.recoveryScore}',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  result!.explanation,
                  style: const TextStyle(fontSize: 16, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                const Text(
                  '??濡?뵹 嶺뚯쉳?????熬곣뫀鍮???⑤베鍮???袁⑤뾼???롪퍒?????낅퉵??',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (result!.holdDecision)
            const _InfoBanner(
              message: '??ル뱴?熬? ????? 嶺뚳퐢?얍칰?筌뤾쑴諭?2~3?????癰????낅슣?섋땻??',
              tone: BannerTone.warning,
            ),
          if (result!.holdDecision) const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result!.tags
                .map(
                  (tag) => Chip(
                    label: Text(
                      tag,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: AppColors.chip,
                    side: BorderSide.none,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '???샑???怨뺣콦 ?????,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _ScoreBar(
                  label: 'Self report',
                  value: result!.componentScores.selfReport,
                  max: 50,
                ),
                _ScoreBar(
                  label: 'Text signal',
                  value: result!.componentScores.textSignal,
                  max: 35,
                ),
                _ScoreBar(
                  label: 'Trend',
                  value: result!.componentScores.trend,
                  max: 10,
                ),
                _ScoreBar(
                  label: 'Voice aux',
                  value: result!.componentScores.voiceAux,
                  max: 5,
                ),
                const SizedBox(height: 6),
                Text(
                  'Confidence ${result!.confidence.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onStartRoutine,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              '?猷먮쳜????戮곗굚',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.label,
    required this.value,
    required this.max,
  });

  final String label;
  final double value;
  final double max;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (value / max).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: AppColors.primary,
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          ),
        ],
      ),
    );
  }
}

class RoutineScreen extends StatelessWidget {
  const RoutineScreen({required this.result, super.key});

  final AnalyzeResponse? result;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return const _CenteredState(
        icon: Icons.self_improvement_outlined,
        title: '?袁⑹춦 ?룐뫂?????곷선??',
        subtitle: '?브쑴苑???袁⑥┷??롢늺 ?곕뗄荑??룐뫂?????뽯뻻??몃빍??',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '異붿쿇 猷⑦떞',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '吏湲?諛붾줈 ?ㅽ뻾?????덈뒗 2~5遺?猷⑦떞',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          ...result!.recommendedRoutines.map(
            (routine) => _SurfaceCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8EBE4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      routine,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum ReportRange { days7, days14, days30, all }

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    required this.result,
    required this.history,
    required this.loading,
    required this.errorMessage,
    required this.onRefresh,
    super.key,
  });

  final AnalyzeResponse? result;
  final List<CheckinHistoryItem> history;
  final bool loading;
  final String errorMessage;
  final Future<void> Function() onRefresh;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportRange _range = ReportRange.days7;

  List<CheckinHistoryItem> _filteredHistory() {
    final source = widget.history;
    if (_range == ReportRange.all) return source;

    final nowUtc = DateTime.now().toUtc();
    final days = switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 36500,
    };

    return source.where((item) {
      final ts = _parseCreatedAt(item.createdAt);
      if (ts == null) return true;
      final diff = nowUtc.difference(ts).inDays;
      return diff <= days;
    }).toList();
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
        SnackBar(content: Text('CSV ????꾨즺: ${file.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV ????ㅽ뙣: $e')));
    }
  }
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.history.isEmpty) {
      return const _CenteredState(
        icon: Icons.hourglass_top_rounded,
        title: '由ы룷??遺덈윭?ㅻ뒗 以?,
        subtitle: '泥댄겕??湲곕줉??媛?몄삤怨??덉뼱??',
      );
    }

    if (widget.history.isEmpty) {
      return const _CenteredState(
        icon: Icons.show_chart_outlined,
        title: '二쇨컙 由ы룷??以鍮?以?,
        subtitle: '泥댄겕???곗씠?곌? ?볦씠硫?由ы룷?멸? ?쒖떆?⑸땲??',
      );
    }

    final filtered = _filteredHistory();
    final base = filtered.isNotEmpty ? filtered : widget.history;

    final latest = base.first;
    final score = latest.recoveryScore;
    final risk = latest.riskScore;
    final chartPoints = base
        .take(7)
        .toList()
        .reversed
        .map((item) => item.recoveryScore / 100)
        .toList();

    final avgRecovery =
        base.map((e) => e.recoveryScore).reduce((a, b) => a + b) / base.length;
    final avgRisk =
        base.map((e) => e.riskScore).reduce((a, b) => a + b) / base.length;

    final tagCount = <String, int>{};
    for (final item in base) {
      for (final tag in item.tags) {
        tagCount[tag] = (tagCount[tag] ?? 0) + 1;
      }
    }
    final sortedTags = tagCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final confidenceBuckets = <String, int>{
      '??쓬 (0.0~0.39)': 0,
      '以묎컙 (0.40~0.69)': 0,
      '?믪쓬 (0.70~1.00)': 0,
    };
    for (final item in base) {
      if (item.confidence < 0.4) {
        confidenceBuckets['??쓬 (0.0~0.39)'] =
            confidenceBuckets['??쓬 (0.0~0.39)']! + 1;
      } else if (item.confidence < 0.7) {
        confidenceBuckets['以묎컙 (0.40~0.69)'] =
            confidenceBuckets['以묎컙 (0.40~0.69)']! + 1;
      } else {
        confidenceBuckets['?믪쓬 (0.70~1.00)'] =
            confidenceBuckets['?믪쓬 (0.70~1.00)']! + 1;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '二쇨컙 由ы룷??,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => unawaited(widget.onRefresh()),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '?덈줈怨좎묠',
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.errorMessage.isNotEmpty)
            _InfoBanner(message: widget.errorMessage, tone: BannerTone.warning),
          if (widget.errorMessage.isNotEmpty) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_exportCsv(context, base)),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('CSV ?대낫?닿린'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SurfaceCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('7??),
                  selected: _range == ReportRange.days7,
                  onSelected: (_) => setState(() => _range = ReportRange.days7),
                ),
                ChoiceChip(
                  label: const Text('14??),
                  selected: _range == ReportRange.days14,
                  onSelected: (_) =>
                      setState(() => _range = ReportRange.days14),
                ),
                ChoiceChip(
                  label: const Text('30??),
                  selected: _range == ReportRange.days30,
                  onSelected: (_) =>
                      setState(() => _range = ReportRange.days30),
                ),
                ChoiceChip(
                  label: const Text('?꾩껜'),
                  selected: _range == ReportRange.all,
                  onSelected: (_) => setState(() => _range = ReportRange.all),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: '理쒓렐 ?뚮났',
                  value: '$score',
                  accent: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  title: '理쒓렐 由ъ뒪??,
                  value: '$risk',
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
                  title: '?됯퇏 ?뚮났',
                  value: avgRecovery.toStringAsFixed(1),
                  accent: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  title: '?됯퇏 由ъ뒪??,
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
                const Text(
                  '?뚮났 ?먯닔 異붿꽭 (理쒕? 7??',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
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
                const Text(
                  'Confidence 遺꾪룷',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ...confidenceBuckets.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DistributionRow(
                      label: entry.key,
                      count: entry.value,
                      total: base.length,
                      color: entry.key.startsWith('??쓬')
                          ? const Color(0xFFD97706)
                          : entry.key.startsWith('以묎컙')
                          ? const Color(0xFF2F6B5F)
                          : const Color(0xFF0F766E),
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
                const Text(
                  '?쒓렇 遺꾪룷 (?곸쐞 6媛?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (sortedTags.isEmpty)
                  const Text(
                    '?꾩쭅 ?쒓렇 ?곗씠?곌? ?놁뒿?덈떎.',
                    style: TextStyle(color: AppColors.muted),
                  )
                else
                  ...sortedTags
                      .take(6)
                      .map(
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
                const Text(
                  '理쒓렐 泥댄겕??,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ...base
                    .take(5)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2F1EC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${item.recoveryScore}',
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.explanation,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatCreatedAt(item.createdAt),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.muted,
                                    ),
                                  ),
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
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (count / total).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$count嫄?(${(ratio * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: color,
            backgroundColor: const Color(0xFFE2E8F0),
          ),
        ),
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
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
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

    final safePoints = points.isEmpty ? [0.0] : points;
    final path = Path();
    for (var i = 0; i < safePoints.length; i++) {
      final x = safePoints.length == 1
          ? size.width / 2
          : (size.width / (safePoints.length - 1)) * i;
      final y = size.height * (1 - safePoints[i].clamp(0, 1));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) =>
      !listEquals(points, oldDelegate.points);
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.margin = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets margin;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

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
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 16, color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
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
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: const Color(0xFFB45309)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 16, color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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
  int _currentRangeDays() {
    return switch (_range) {
      ReportRange.days7 => 7,
      ReportRange.days14 => 14,
      ReportRange.days30 => 30,
      ReportRange.all => 365,
    };
  }

  Future<void> _exportLocalPdf(
    BuildContext context,
    List<CheckinHistoryItem> rows,
  ) async {
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
      final days = _currentRangeDays();

      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, child: pw.Text('Sumpyo Local Report')),
            pw.Text('Range: last $days days'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local PDF save failed: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Server PDF save failed: $e')));
    }
  }

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
      child: Text(
        message,
        style: const TextStyle(fontSize: 15, color: AppColors.text),
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
      recommendedRoutines: (json['recommended_routines'] as List<dynamic>)
          .cast<String>(),
      componentScores: ComponentScores.fromJson(
        json['component_scores'] as Map<String, dynamic>,
      ),
    );
  }
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
        final uri = Uri.parse(
          '$_baseUrl/stt?language=$language&profile=$profile',
        );
        final req = http.MultipartRequest('POST', uri);
        req.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamed = await req.send().timeout(
          Duration(seconds: timeoutSec),
        );
        final body = await streamed.stream.bytesToString();

        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          final msg = _extractError(body) ?? 'HTTP ${streamed.statusCode}';
          throw Exception(msg);
        }

        return STTResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
      } on TimeoutException {
        lastError = Exception('STT request timeout');
      } on SocketException {
        lastError = Exception(
          'Cannot reach API server. Start backend at port 8000.',
        );
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

