import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sumpyo_mobile/main.dart';

void main() {
  testWidgets('Sumpyo home screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SumpyoApp());
    expect(find.text('숨표 체크인'), findsOneWidget);
    expect(find.text('지금 분석'), findsOneWidget);
  });

  testWidgets('Tag drill-down search filters rows', (
    WidgetTester tester,
  ) async {
    final rows = <CheckinHistoryItem>[
      CheckinHistoryItem(
        id: 1,
        createdAt: '2026-04-18 10:00:00',
        recoveryScore: 60,
        riskScore: 40,
        confidence: 0.75,
        holdDecision: false,
        tags: const ['anxiety'],
        explanation: 'anxiety from deadline',
      ),
      CheckinHistoryItem(
        id: 2,
        createdAt: '2026-04-18 11:00:00',
        recoveryScore: 70,
        riskScore: 30,
        confidence: 0.82,
        holdDecision: false,
        tags: const ['anxiety'],
        explanation: 'stable mood',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: TagDrilldownScreen(tag: 'anxiety', rows: rows),
      ),
    );

    expect(
      find.textContaining('conf=0.75 · anxiety from deadline'),
      findsOneWidget,
    );
    expect(find.textContaining('stable mood'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'deadline');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('conf=0.75 · anxiety from deadline'),
      findsOneWidget,
    );
    expect(find.textContaining('stable mood'), findsNothing);
  });

  testWidgets('Tag drill-down pagination buttons state', (
    WidgetTester tester,
  ) async {
    final rows = List<CheckinHistoryItem>.generate(
      9,
      (i) => CheckinHistoryItem(
        id: i + 1,
        createdAt: '2026-04-18 10:00:${(i % 60).toString().padLeft(2, '0')}',
        recoveryScore: 50 + i,
        riskScore: 50 - (i % 10),
        confidence: 0.6,
        holdDecision: false,
        tags: const ['pressure'],
        explanation: 'item $i',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TagDrilldownScreen(tag: 'pressure', rows: rows),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Prev'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('Next'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final prevBtn = find.widgetWithText(OutlinedButton, 'Prev');
    final nextBtn = find.widgetWithText(OutlinedButton, 'Next');
    expect(prevBtn, findsOneWidget);
    expect(nextBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(prevBtn).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(nextBtn).onPressed, isNotNull);

    await tester.ensureVisible(nextBtn);
    await tester.pumpAndSettle();
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(prevBtn).onPressed, isNotNull);
  });

  testWidgets('Tag drill-down confidence filter changes results', (
    WidgetTester tester,
  ) async {
    final rows = <CheckinHistoryItem>[
      CheckinHistoryItem(
        id: 1,
        createdAt: '2026-04-18 10:00:00',
        recoveryScore: 40,
        riskScore: 60,
        confidence: 0.20,
        holdDecision: false,
        tags: const ['fatigue'],
        explanation: 'low confidence sample',
      ),
      CheckinHistoryItem(
        id: 2,
        createdAt: '2026-04-18 11:00:00',
        recoveryScore: 85,
        riskScore: 15,
        confidence: 0.90,
        holdDecision: false,
        tags: const ['fatigue'],
        explanation: 'high confidence sample',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: TagDrilldownScreen(tag: 'fatigue', rows: rows),
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'low'));
    await tester.pumpAndSettle();
    expect(find.textContaining('low confidence sample'), findsOneWidget);
    expect(find.textContaining('high confidence sample'), findsNothing);
  });

  testWidgets('Tag drill-down restores initial state on open', (
    WidgetTester tester,
  ) async {
    final rows = List<CheckinHistoryItem>.generate(
      10,
      (i) => CheckinHistoryItem(
        id: i + 1,
        createdAt: '2026-04-18 10:00:${(i % 60).toString().padLeft(2, '0')}',
        recoveryScore: 50 + i,
        riskScore: 50 - (i % 10),
        confidence: i == 8 ? 0.22 : 0.88,
        holdDecision: false,
        tags: const ['pressure'],
        explanation: 'item $i',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TagDrilldownScreen(
          tag: 'pressure',
          rows: rows,
          initialState: const TagDrilldownViewState(
            filter: TagConfidenceFilter.low,
            sort: TagSort.newest,
            page: 0,
            query: 'item 8',
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ChoiceChip, 'low'), findsOneWidget);
    expect(find.textContaining('conf=0.22 · item 8'), findsOneWidget);
    expect(find.textContaining('conf=0.88 · item 1'), findsNothing);
  });
  testWidgets('Home STT controls include auto profile and network selector', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SumpyoApp());

    final dropdowns = tester.widgetList<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdowns.length, 2);

    final profileItems = dropdowns.first.items ?? const <DropdownMenuItem<String>>[];
    final profileValues = profileItems
        .map((e) => e.value)
        .whereType<String>()
        .toList();
    expect(
      profileValues,
      containsAll(<String>['fast', 'balanced', 'accurate', 'auto']),
    );

    final networkItems = dropdowns.last.items ?? const <DropdownMenuItem<String>>[];
    final networkValues = networkItems
        .map((e) => e.value)
        .whereType<String>()
        .toList();
    expect(networkValues, containsAll(<String>['poor', 'normal', 'good']));
  });
}
