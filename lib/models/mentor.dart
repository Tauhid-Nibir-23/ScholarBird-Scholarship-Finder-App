/// Domain model for a faculty mentor surfaced in the Mentor Hub.
///
/// Designed to be Firestore-friendly: every field is optional where it makes
/// sense, and a `fromMap` factory is provided so the same shape can be
/// deserialised from a Firestore document later without UI changes.

/// Canonical department keys used by the filter chips. Keep the string
/// identifiers stable — they are persisted in the sample data source and
/// are referenced from the Mentor Hub UI.
enum MentorDepartment {
  all('All'),
  computerScience('Computer Science'),
  electricalEngineering('Electrical Engineering'),
  business('Business'),
  mechanical('Mechanical'),
  civil('Civil'),
  others('Others');

  const MentorDepartment(this.label);

  /// Human-friendly label used in the UI.
  final String label;

  /// Returns the matching enum value for a free-form department string.
  /// Falls back to [others] so unrecognised values still render.
  static MentorDepartment fromString(String? raw) {
    if (raw == null) return MentorDepartment.others;
    final normalized = raw.trim().toLowerCase();
    return MentorDepartment.values.firstWhere(
      (d) => d != MentorDepartment.all && d.label.toLowerCase() == normalized,
      orElse: () => MentorDepartment.others,
    );
  }
}

/// Immutable representation of a single mentor card.
class Mentor {
  const Mentor({
    required this.id,
    required this.name,
    required this.designation,
    required this.department,
    required this.university,
    required this.researchInterests,
    required this.bio,
    required this.email,
    this.photoUrl,
    this.phone,
    this.officeRoom,
    this.availableDays = const <String>[],
    this.availableTime,
  });

  /// Stable identifier — required so the UI can track cards and the data
  /// source can dedupe records when swapping in a Firestore collection.
  final String id;

  /// Full display name shown as the card title.
  final String name;

  /// e.g. "Professor", "Associate Professor", "Lecturer".
  final String designation;

  /// One of the canonical departments; keeps filtering consistent.
  final MentorDepartment department;

  /// Hosting university/institution.
  final String university;

  /// Short list of research areas shown as inline tags.
  final List<String> researchInterests;

  /// One or two sentence biography.
  final String bio;

  /// Email used by the Email and Copy actions.
  final String email;

  /// Optional portrait URL. When null/empty the card renders initials.
  final String? photoUrl;

  /// Optional phone number for the Call action.
  final String? phone;

  /// Optional physical office room label.
  final String? officeRoom;

  /// Days the mentor is reachable, e.g. ['Sun', 'Tue'].
  final List<String> availableDays;

  /// Optional human-friendly time window, e.g. "10:00 AM – 1:00 PM".
  final String? availableTime;

  /// Convenience constructor that builds a [Mentor] from a Firestore-style
  /// map. Unknown keys are ignored; missing optionals fall back to defaults.
  factory Mentor.fromMap(Map<String, dynamic> map) => Mentor(
        id: (map['id'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        designation: (map['designation'] ?? '').toString(),
        department: MentorDepartment.fromString(map['department'] as String?),
        university: (map['university'] ?? '').toString(),
        researchInterests: _stringList(map['researchInterests']),
        bio: (map['bio'] ?? '').toString(),
        email: (map['email'] ?? '').toString(),
        photoUrl: map['photoUrl'] as String?,
        phone: map['phone'] as String?,
        officeRoom: map['officeRoom'] as String?,
        availableDays: _stringList(map['availableDays']),
        availableTime: map['availableTime'] as String?,
      );

  /// Returns a copy with the selected fields replaced. Useful when a
  /// future remote-sync flow wants to refresh only one field.
  Mentor copyWith({
    String? id,
    String? name,
    String? designation,
    MentorDepartment? department,
    String? university,
    List<String>? researchInterests,
    String? bio,
    String? email,
    String? photoUrl,
    String? phone,
    String? officeRoom,
    List<String>? availableDays,
    String? availableTime,
  }) =>
      Mentor(
        id: id ?? this.id,
        name: name ?? this.name,
        designation: designation ?? this.designation,
        department: department ?? this.department,
        university: university ?? this.university,
        researchInterests: researchInterests ?? this.researchInterests,
        bio: bio ?? this.bio,
        email: email ?? this.email,
        photoUrl: photoUrl ?? this.photoUrl,
        phone: phone ?? this.phone,
        officeRoom: officeRoom ?? this.officeRoom,
        availableDays: availableDays ?? this.availableDays,
        availableTime: availableTime ?? this.availableTime,
      );

  /// True when the mentor's free-text fields match [query] (case-insensitive).
  /// Research interests are searched so a query like "robotics" lands on a
  /// mentor whose research list contains that word.
  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;

    final haystack = <String>[
      name,
      designation,
      department.label,
      university,
      bio,
      email,
      ...researchInterests,
    ].map((s) => s.toLowerCase()).toList();

    for (final value in haystack) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  /// Returns true if this mentor belongs to [filter] (or any/all).
  bool matchesFilter(MentorDepartment filter) {
    if (filter == MentorDepartment.all) return true;
    if (filter == MentorDepartment.others) {
      // "Others" means "not one of the explicitly enumerated departments".
      const named = {
        MentorDepartment.computerScience,
        MentorDepartment.electricalEngineering,
        MentorDepartment.business,
        MentorDepartment.mechanical,
        MentorDepartment.civil,
      };
      return !named.contains(department);
    }
    return department == filter;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return const <String>[];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Mentor && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
