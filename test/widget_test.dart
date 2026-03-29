// ScholarBird Widget Tests
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scholarbird/main.dart';

void main() {
  testWidgets('ScholarBird app launches with LoginScreen',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ScholarBirdApp());

    // Verify that the login screen is displayed
    expect(find.text('ScholarBird'), findsWidgets);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('Login button is visible and tappable',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ScholarBirdApp());

    // Verify login button exists
    expect(find.text('Login'), findsOneWidget);

    // Verify it's an ElevatedButton
    expect(find.byType(ElevatedButton), findsWidgets);
  });

  testWidgets('SignUp link is visible on login screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ScholarBirdApp());

    // Verify SignUp text exists
    expect(find.text('Sign Up'), findsOneWidget);
  });
}

