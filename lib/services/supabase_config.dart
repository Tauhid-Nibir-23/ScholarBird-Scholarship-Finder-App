/// Centralised Supabase configuration. Values are sourced from the
/// `.env` file when available, with hard-coded fallbacks so the app
/// keeps working on platforms (notably Flutter web) where `.env` is not
/// automatically bundled.
///
/// The legacy `anon` JWT (starts with `eyJhbGciOi...`) is used because
/// `supabase_flutter` predates full support for the new
/// `sb_publishable_...` format.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase project credentials and bucket names.
class SupabaseConfig {
  const SupabaseConfig._();

  /// Project URL (e.g. `https://xyz.supabase.co`).
  static String get url => dotenv.maybeGet('SUPABASE_URL') ?? _url;

  /// Legacy `anon` JWT used by the Flutter SDK.
  static String get anonKey => dotenv.maybeGet('SUPABASE_ANON_KEY') ?? _anonKey;

  /// Storage bucket that holds user-uploaded documents.
  static const String documentsBucket = 'documents';

  /// Storage bucket that holds user profile pictures (one per user:
  /// `profile-images/{uid}.jpg`).
  static const String profileImagesBucket = 'profile-images';

  /// Storage bucket that holds mentor profile pictures (one per mentor:
  /// `mentor-images/{mentorId}.jpg`).
  static const String mentorImagesBucket = 'mentor-images';

  /// Storage bucket that holds scholarship banner images (one per
  /// scholarship: `scholarship-banners/{scholarshipId}.jpg`).
  static const String scholarshipBannersBucket = 'scholarship-banners';

  /// Storage bucket that holds notification images for broadcasts.
  static const String notificationImagesBucket = 'notification-images';

  /// Storage bucket that holds admin profile pictures (one per admin:
  /// `admin-images/{uid}.jpg`).
  static const String adminImagesBucket = 'admin-images';

  // Hard-coded fallback credentials. The legacy `anon` JWT is what the
  // current Flutter SDK accepts. Replace if you rotate keys.
  static const String _url = 'https://unhqqupfesjhjzjioweg.supabase.co';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVuaHFxdXBmZXNqaGp6amlvd2VnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4NjQ5NTUsImV4cCI6MjEwMTQ0MDk1NX0.va0_M7tUwYdiQfle6p7VpaDB50QTFCRemYsItEaEEtA';
}
