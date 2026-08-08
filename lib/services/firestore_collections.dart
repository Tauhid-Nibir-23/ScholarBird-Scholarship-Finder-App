/// Centralised Firestore collection names.
///
/// Keeping collection identifiers in one place prevents the "Reference Point"
/// (formerly `mentors`, now `reference_points`) and the "Mentor Hub"
/// marketplace from drifting apart. Both feature areas must stay logically
/// separate but share the same naming convention.
library;

/// Top-level user accounts.
const String kCollectionUsers = 'users';

/// Scholarship catalogue surfaced in the discovery flow.
const String kCollectionScholarships = 'scholarships';

/// User-submitted applications for scholarships.
const String kCollectionApplications = 'applications';

/// Activity log entries (admin only).
const String kCollectionActivityLogs = 'activity_logs';

/// Push notifications broadcast target.
const String kCollectionNotifications = 'notifications';

// ─── Reference Point (Professor / Research Directory) ───────────────────────
/// Faculty mentors, professors, research contacts, labs, universities.
///
/// Historical note: this collection used to be called `mentors`. It was
/// renamed to `reference_points` because the new paid Mentor Hub owns the
/// "mentor" noun for the marketplace. The legacy collection is left
/// untouched and obsolete; a one-time migration script in
/// `tools/migrate_mentors_to_reference_points.dart` copies documents.
const String kCollectionReferencePoints = 'reference_points';

// ─── Mentor Hub (Paid Mentor Marketplace) ───────────────────────────────────
/// Paid mentor profiles surfaced in the Mentor Hub marketplace.
const String kCollectionMentorsMarketplace = 'mentors_marketplace';

/// Per-mentor session packages (hourly, multi-session, etc.).
const String kCollectionMentorPackages = 'mentor_packages';

/// Booking lifecycle records (pending, confirmed, completed, cancelled).
const String kCollectionMentorBookings = 'mentor_bookings';

/// Post-session reviews from students.
const String kCollectionMentorReviews = 'mentor_reviews';
