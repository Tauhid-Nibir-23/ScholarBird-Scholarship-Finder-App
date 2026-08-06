/// Identifies the scholarship flavour an SOP is being written for.
///
/// The SOP generator uses this enum to pick the right tone, structure and
/// emphasis hints that Gemini needs to produce a programme-tailored draft.
enum ScholarshipType {
  daad(
    id: 'daad',
    label: 'DAAD Scholarship',
    country: 'Germany',
    description:
        'German Academic Exchange Service — emphasises academic excellence, '
            'development-related impact and a return-to-home-country motivation.',
  ),
  erasmus(
    id: 'erasmus',
    label: 'Erasmus Mundus',
    country: 'European Union',
    description:
        'EU joint-master programme — values international exposure, mobility '
            'across partner countries and intercultural competence.',
  ),
  chevening(
    id: 'chevening',
    label: 'Chevening Scholarship',
    country: 'United Kingdom',
    description:
        'UK Foreign Office flagship — spotlights leadership, network-building '
            'and a clear plan to contribute to the applicant\'s home country.',
  ),
  commonwealth(
    id: 'commonwealth',
    label: 'Commonwealth Scholarship',
    country: 'United Kingdom',
    description:
        'Funded by the Commonwealth Scholarship Commission — focuses on '
            'development impact, academic merit and serving under-served '
            'communities.',
  ),
  generic(
    id: 'generic',
    label: 'Generic Scholarship',
    country: '',
    description:
        'A neutral SOP structure suitable when the programme does not '
            'require a specific framing.',
  );

  const ScholarshipType({
    required this.id,
    required this.label,
    required this.country,
    required this.description,
  });

  final String id;
  final String label;
  final String country;
  final String description;

  static ScholarshipType fromId(String? id) {
    if (id == null) return ScholarshipType.generic;
    for (final type in ScholarshipType.values) {
      if (type.id == id) return type;
    }
    return ScholarshipType.generic;
  }
}
