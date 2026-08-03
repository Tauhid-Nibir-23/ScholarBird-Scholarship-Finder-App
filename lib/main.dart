import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'admin/admin_dashboard.dart';
import 'screens/home/home_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/scholarbird_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // GeminiService reads its key only when the advisor is used. Keeping this
  // non-fatal lets the rest of the app run while a developer configures .env.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized, ignore the error
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  runApp(const ScholarBirdApp());
}

class ScholarBirdApp extends StatelessWidget {
  const ScholarBirdApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ScholarBird',
        theme: ScholarBirdTheme.light(),

        // Start app from splash screen
        initialRoute: '/splash',

        routes: {
          '/splash': (context) => const SplashScreen(),
          '/onboarding': (context) => const OnboardingScreen(),
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignUpScreen(),
          '/home': (context) => const HomeScreen(),
          '/admin': (context) => const AdminDashboard(),
        },
      );
}
