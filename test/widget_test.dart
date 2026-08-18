// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:dictation_application/main.dart';

void main() {
  testWidgets('JunEdu app shows the exam list and app title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const JunEduApp());

    expect(find.text('JunEdu'), findsOneWidget);
    expect(find.text('Exam Library'), findsOneWidget);
  });
}
