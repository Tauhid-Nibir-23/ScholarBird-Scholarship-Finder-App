/// Domain model for an academic reference attached to a user.
///
/// References are persisted as Firestore documents at
/// `users/{uid}/references/{referenceId}`, where the id is `reference1` or
/// `reference2`. The UI keeps up to two slots, but the data model is
/// flexible enough to hold more.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// How the reference is related to the applicant. Free text is also allowed
/// via the [ReferenceModel.customRelationship] field for labels that do not
/// fit one of the canonical options.
enum RelationshipType {
  academicSupervisor('Academic Supervisor', 'academicSupervisor'),
  courseTeacher('Course Teacher', 'courseTeacher'),
  researchMentor('Research Mentor', 'researchMentor'),
  thesisSupervisor('Thesis Supervisor', 'thesisSupervisor');

  const RelationshipType(this.label, this.firestoreId);

  /// Human-friendly label used in the UI.
  final String label;

  /// Stable identifier persisted in Firestore.
  final String firestoreId;

  /// Returns the enum value for a stored id, or null if unknown.
  static RelationshipType? tryFromId(String? id) {
    if (id == null) return null;
    for (final value in RelationshipType.values) {
      if (value.firestoreId == id) return value;
    }
    return null;
  }
}

/// Immutable representation of an academic reference.
class ReferenceModel {
  const ReferenceModel({
    required this.id,
    required this.fullName,
    required this.designation,
    required this.department,
    required this.university,
    required this.email,
    required this.phone,
    required this.relationship,
    this.customRelationship,
  });

  /// Firestore document id — e.g. `reference1` or `reference2`.
  final String id;

  /// Full name of the referee.
  final String fullName;

  /// Job title, e.g. "Associate Professor".
  final String designation;

  /// Department the referee belongs to.
  final String department;

  /// Institution the referee is affiliated with.
  final String university;

  /// Official institution email.
  final String email;

  /// Phone number (raw, formatting applied at render time).
  final String phone;

  /// Canonical relationship enum value, if any.
  final RelationshipType? relationship;

  /// Free-text relationship label. Used when the canonical set is
  /// insufficient, or to preserve the original user input.
  final String? customRelationship;

  /// Convenience: the label that should be displayed in the UI.
  String get relationshipLabel {
    final custom = customRelationship?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return relationship?.label ?? 'Reference';
  }

  /// Returns true when the bare-minimum fields have been filled in.
  bool get isComplete =>
      fullName.trim().isNotEmpty &&
      email.trim().isNotEmpty &&
      university.trim().isNotEmpty;

  /// Builds a [ReferenceModel] from a Firestore document snapshot.
  factory ReferenceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return ReferenceModel.fromMap(data, fallbackId: snapshot.id);
  }

  /// Builds a [ReferenceModel] from a Firestore map. [fallbackId] is used
  /// when the map does not carry an explicit id.
  factory ReferenceModel.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final id = (map['id'] as String?) ?? fallbackId ?? '';
    return ReferenceModel(
      id: id,
      fullName: (map['fullName'] ?? '').toString(),
      designation: (map['designation'] ?? '').toString(),
      department: (map['department'] ?? '').toString(),
      university: (map['university'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      relationship: RelationshipType.tryFromId(map['relationship'] as String?),
      customRelationship: map['customRelationship'] as String?,
    );
  }

  /// Converts the model to a Firestore-friendly map.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'fullName': fullName.trim(),
        'designation': designation.trim(),
        'department': department.trim(),
        'university': university.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'relationship': relationship?.firestoreId,
        'customRelationship': customRelationship?.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Returns a copy with the supplied fields replaced.
  ReferenceModel copyWith({
    String? id,
    String? fullName,
    String? designation,
    String? department,
    String? university,
    String? email,
    String? phone,
    RelationshipType? relationship,
    String? customRelationship,
  }) =>
      ReferenceModel(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
        designation: designation ?? this.designation,
        department: department ?? this.department,
        university: university ?? this.university,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        relationship: relationship ?? this.relationship,
        customRelationship: customRelationship ?? this.customRelationship,
      );

  /// Returns an empty reference record for the given slot id.
  factory ReferenceModel.empty(String id) => ReferenceModel(
        id: id,
        fullName: '',
        designation: '',
        department: '',
        university: '',
        email: '',
        phone: '',
        relationship: null,
        customRelationship: null,
      );
}
