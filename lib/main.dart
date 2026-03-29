import 'package:flutter/material.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/home/home_screen.dart';

void main() {
  runApp(const ScholarBirdApp());
}

class ScholarBirdApp extends StatelessWidget {
  const ScholarBirdApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ScholarBird',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),

      // Start app from splash screen
      initialRoute: '/splash',

      routes: {
        '/splash': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
}
