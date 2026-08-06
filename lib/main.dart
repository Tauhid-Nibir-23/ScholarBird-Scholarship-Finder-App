/// Application entry point and route registration for ScholarBird.

// The SOP route helper closure below refers to [SopGeneratorScreen] inside a
// builder lambda; the analyzer can't always follow the reference through a
// generic `Map<String, WidgetBuilder>` literal, so silence the false positive.
// ignore_for_file: unused_import

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_dashboard.dart';
import 'ai_hub/profile_analysis/profile_analysis_screen.dart';
import 'ai_hub/sop/sop_generator_screen.dart';
import 'firebase_options.dart';
import 'screens/ai_advisor/chat_screen.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/subscription_provider.dart';
import 'services/admin_access_gate.dart';
import 'services/supabase_config.dart';
import 'theme/scholarbird_theme.dart';
import 'widgets/premium_guard.dart';

/// Initializes Flutter, Firebase, and app-wide configuration before launch.
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

  // Initialise Supabase for document uploads. Reading the project URL and
  // publishable key from `.env` keeps the secret out of source control.
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (_) {
    // Non-fatal: the rest of the app keeps working even if Supabase is
    // temporarily unreachable. Upload actions will surface a clear error.
  }

  runApp(const ScholarBirdApp());
}

/// Root widget that defines the app theme and named routes.
class ScholarBirdApp extends StatefulWidget {
  const ScholarBirdApp({super.key});

  @override
  State<ScholarBirdApp> createState() => _ScholarBirdAppState();
}

class _ScholarBirdAppState extends State<ScholarBirdApp> {
  // App-wide reactive subscription state. Created once and shared with the
  // widget tree through [SubscriptionProviderScope] so every premium-gated
  // screen / widget reads from the same source of truth.
  final SubscriptionProvider _subscriptionProvider = SubscriptionProvider()
    ..start();

  @override
  void dispose() {
    _subscriptionProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SubscriptionProviderScope(
        provider: _subscriptionProvider,
        child: MaterialApp(
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
            '/verify-email': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args is EmailVerificationScreenArgs) {
                return EmailVerificationScreen(
                  email: args.email,
                  reason: args.reason,
                );
              }
              // Fallback for a missing/invalid arguments payload — the user
              // can still recover by going back to login.
              return const EmailVerificationScreen(
                email: '',
                reason: EmailVerificationReason.unverifiedLogin,
              );
            },
            '/home': (context) => const HomeScreen(),
            '/admin': (context) => const AdminAccessGate(child: AdminDashboard()),
            '/ai-hub/sop': (context) => const SopGeneratorScreen(),
            '/ai-hub/chat': (context) => const ChatScreen(),
            '/ai-hub/profile-analysis': (context) =>
                const ProfileAnalysisScreen(),
          },
        ),
      );
}
