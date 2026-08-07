/// Data model + curated seed list for the Community feature.
///
/// Each [CommunityGroup] is a scholarship community for a country. The
/// static [CommunityGroup.all] list drives the list/feed and the
/// detail screen; the [CommunityGroup.featured] getter picks the top
/// picks for the horizontal carousel.
library;

import 'package:flutter/material.dart';

/// Geographic region used to group communities in the list.
enum CommunityRegion { asia, europe, africa, americas, oceania, middleEast }

/// Pretty label for each [CommunityRegion] used in the section headers.
extension CommunityRegionLabel on CommunityRegion {
  String get display {
    switch (this) {
      case CommunityRegion.asia:
        return 'Asia';
      case CommunityRegion.europe:
        return 'Europe';
      case CommunityRegion.africa:
        return 'Africa';
      case CommunityRegion.americas:
        return 'Americas';
      case CommunityRegion.oceania:
        return 'Oceania';
      case CommunityRegion.middleEast:
        return 'Middle East';
    }
  }
}

/// A single scholarship community.
@immutable
class CommunityGroup {
  const CommunityGroup({
    required this.id,
    required this.name,
    required this.country,
    required this.region,
    required this.members,
    required this.online,
    required this.bio,
    required this.bannerGradient,
    required this.flagEmoji,
    required this.hashtag,
    required this.initials,
  });

  final String id;
  final String name;
  final String country;
  final CommunityRegion region;
  final int members;
  final int online;
  final String bio;
  final List<Color> bannerGradient;
  final String flagEmoji;
  final String hashtag;
  final String initials;

  /// Top five picks shown in the "Featured for you" carousel.
  static List<CommunityGroup> get featured => all.take(5).toList();

  /// Curated list of country communities.
  static const List<CommunityGroup> all = [
    // Asia
    CommunityGroup(
      id: 'tl',
      name: 'Scholarships for the Timor-Leste Students',
      country: 'Timor-Leste',
      region: CommunityRegion.asia,
      members: 62,
      online: 18,
      bio:
          'Welcome Scholarships for the Timor-Leste Students group. Share opportunities, deadlines and visa tips.',
      bannerGradient: [
        Color(0xFF1E54FF),
        Color(0xFF3D78FF),
      ],
      flagEmoji: '🇹🇱',
      hashtag: '#TLScholars',
      initials: 'TL',
    ),
    CommunityGroup(
      id: 'id',
      name: 'Scholarships for the Indonesian Students',
      country: 'Indonesia',
      region: CommunityRegion.asia,
      members: 52,
      online: 14,
      bio:
          'Welcome Scholarships for the Indonesian Students. A hub for beasiswa info, IELTS prep and alumni mentors.',
      bannerGradient: [
        Color(0xFFE03A53),
        Color(0xFFFF6B7E),
      ],
      flagEmoji: '🇮🇩',
      hashtag: '#IDScholars',
      initials: 'ID',
    ),
    CommunityGroup(
      id: 'my',
      name: 'Scholarships for the Malaysian Students',
      country: 'Malaysia',
      region: CommunityRegion.asia,
      members: 57,
      online: 21,
      bio:
          'Welcome Scholarships for the Malaysian Students. From JPA to MEXT - discuss scholarships, foundations and CGPA boosters.',
      bannerGradient: [
        Color(0xFFCC1F3A),
        Color(0xFFE63A55),
      ],
      flagEmoji: '🇲🇾',
      hashtag: '#MYScholars',
      initials: 'MY',
    ),
    CommunityGroup(
      id: 'mm',
      name: 'Scholarships for the Myanmar Students',
      country: 'Myanmar',
      region: CommunityRegion.asia,
      members: 36,
      online: 12,
      bio:
          'Welcome Scholarships for the Myanmar Students. Share ASEAN scholarship calls, IELTS prep tips and visa guidance.',
      bannerGradient: [
        Color(0xFF34A853),
        Color(0xFFFFC93C),
      ],
      flagEmoji: '🇲🇲',
      hashtag: '#MMScholars',
      initials: 'MM',
    ),
    CommunityGroup(
      id: 'vn',
      name: 'Scholarships for the Vietnamese Students',
      country: 'Vietnam',
      region: CommunityRegion.asia,
      members: 48,
      online: 11,
      bio:
          'Welcome Scholarships for the Vietnamese Students. Vallet, AASA and global fellowships discussion.',
      bannerGradient: [
        Color(0xFFDA251D),
        Color(0xFFFF4F4F),
      ],
      flagEmoji: '🇻🇳',
      hashtag: '#VNScholars',
      initials: 'VN',
    ),
    CommunityGroup(
      id: 'ph',
      name: 'Scholarships for the Filipino Students',
      country: 'Philippines',
      region: CommunityRegion.asia,
      members: 71,
      online: 26,
      bio:
          'Welcome Scholarships for the Filipino Students. CHED, DOST and abroad scholarship threads.',
      bannerGradient: [
        Color(0xFF0038A8),
        Color(0xFF1F5BE0),
      ],
      flagEmoji: '🇵🇭',
      hashtag: '#PHScholars',
      initials: 'PH',
    ),
    CommunityGroup(
      id: 'th',
      name: 'Scholarships for the Thai Students',
      country: 'Thailand',
      region: CommunityRegion.asia,
      members: 39,
      online: 9,
      bio:
          'Welcome Scholarships for the Thai Students. From King Scholarship to Fulbright Thailand.',
      bannerGradient: [
        Color(0xFFA51931),
        Color(0xFFED1C24),
      ],
      flagEmoji: '🇹🇭',
      hashtag: '#THScholars',
      initials: 'TH',
    ),
    CommunityGroup(
      id: 'jp',
      name: 'Scholarships for the Japanese Students',
      country: 'Japan',
      region: CommunityRegion.asia,
      members: 64,
      online: 23,
      bio:
          'Welcome Scholarships for the Japanese Students. MEXT, JASSO and university-specific programs.',
      bannerGradient: [
        Color(0xFFBC002D),
        Color(0xFFE63950),
      ],
      flagEmoji: '🇯🇵',
      hashtag: '#JPScholars',
      initials: 'JP',
    ),
    CommunityGroup(
      id: 'kr',
      name: 'Scholarships for the Korean Students',
      country: 'South Korea',
      region: CommunityRegion.asia,
      members: 53,
      online: 17,
      bio:
          'Welcome Scholarships for the Korean Students. KGSP, university track and TOPIK prep.',
      bannerGradient: [
        Color(0xFF003478),
        Color(0xFF1F5BE0),
      ],
      flagEmoji: '🇰🇷',
      hashtag: '#KRScholars',
      initials: 'KR',
    ),

    // Europe
    CommunityGroup(
      id: 'gb',
      name: 'Scholarships for the United Kingdom Students',
      country: 'United Kingdom',
      region: CommunityRegion.europe,
      members: 84,
      online: 31,
      bio:
          'Welcome Scholarships for the UK Students. Chevening, Commonwealth and university-specific awards.',
      bannerGradient: [
        Color(0xFF012169),
        Color(0xFF2C5DD6),
      ],
      flagEmoji: '🇬🇧',
      hashtag: '#UKScholars',
      initials: 'UK',
    ),
    CommunityGroup(
      id: 'de',
      name: 'Scholarships for the German Students',
      country: 'Germany',
      region: CommunityRegion.europe,
      members: 92,
      online: 28,
      bio:
          'Welcome Scholarships for the German Students. DAAD, Deutschlandstipendium and tuition-free programs.',
      bannerGradient: [
        Color(0xFF000000),
        Color(0xFFFFCE00),
      ],
      flagEmoji: '🇩🇪',
      hashtag: '#DEScholars',
      initials: 'DE',
    ),
    CommunityGroup(
      id: 'fr',
      name: 'Scholarships for the French Students',
      country: 'France',
      region: CommunityRegion.europe,
      members: 66,
      online: 19,
      bio:
          'Welcome Scholarships for the French Students. Eiffel, Erasmus and Campus France support.',
      bannerGradient: [
        Color(0xFF0055A4),
        Color(0xFFEF4135),
      ],
      flagEmoji: '🇫🇷',
      hashtag: '#FRScholars',
      initials: 'FR',
    ),
    CommunityGroup(
      id: 'nl',
      name: 'Scholarships for the Dutch Students',
      country: 'Netherlands',
      region: CommunityRegion.europe,
      members: 58,
      online: 22,
      bio:
          'Welcome Scholarships for the Dutch Students. Holland Scholarship, Orange Tulip and Leiden Excellence.',
      bannerGradient: [
        Color(0xFFAE1C28),
        Color(0xFF21468B),
      ],
      flagEmoji: '🇳🇱',
      hashtag: '#NLScholars',
      initials: 'NL',
    ),

    // Africa
    CommunityGroup(
      id: 'ng',
      name: 'Scholarships for the Nigerian Students',
      country: 'Nigeria',
      region: CommunityRegion.africa,
      members: 88,
      online: 33,
      bio:
          'Welcome Scholarships for the Nigerian Students. PTDF, AGIP, Mastercard Foundation and more.',
      bannerGradient: [
        Color(0xFF008751),
        Color(0xFF34A853),
      ],
      flagEmoji: '🇳🇬',
      hashtag: '#NGScholars',
      initials: 'NG',
    ),
    CommunityGroup(
      id: 'ke',
      name: 'Scholarships for the Kenyan Students',
      country: 'Kenya',
      region: CommunityRegion.africa,
      members: 47,
      online: 12,
      bio:
          'Welcome Scholarships for the Kenyan Students. Equity Wings to Fly, Mastercard Foundation.',
      bannerGradient: [
        Color(0xFF000000),
        Color(0xFFBB0000),
      ],
      flagEmoji: '🇰🇪',
      hashtag: '#KEScholars',
      initials: 'KE',
    ),
    CommunityGroup(
      id: 'gh',
      name: 'Scholarships for the Ghanaian Students',
      country: 'Ghana',
      region: CommunityRegion.africa,
      members: 41,
      online: 10,
      bio:
          'Welcome Scholarships for the Ghanaian Students. Ghana Scholarships Secretariat and abroad opportunities.',
      bannerGradient: [
        Color(0xFFCE1126),
        Color(0xFFFCD116),
      ],
      flagEmoji: '🇬🇭',
      hashtag: '#GHScholars',
      initials: 'GH',
    ),
    CommunityGroup(
      id: 'za',
      name: 'Scholarships for the South African Students',
      country: 'South Africa',
      region: CommunityRegion.africa,
      members: 55,
      online: 18,
      bio:
          'Welcome Scholarships for the South African Students. NSFAS, Mandela Rhodes and Fulbright.',
      bannerGradient: [
        Color(0xFF007749),
        Color(0xFFFFB81C),
      ],
      flagEmoji: '🇿🇦',
      hashtag: '#SAScholars',
      initials: 'ZA',
    ),

    // Americas
    CommunityGroup(
      id: 'us',
      name: 'Scholarships for the United States Students',
      country: 'United States',
      region: CommunityRegion.americas,
      members: 102,
      online: 41,
      bio:
          'Welcome Scholarships for the U.S. Students. Fulbright, athletics scholarships and university aid.',
      bannerGradient: [
        Color(0xFFB22234),
        Color(0xFF3C3B6E),
      ],
      flagEmoji: '🇺🇸',
      hashtag: '#USScholars',
      initials: 'US',
    ),
    CommunityGroup(
      id: 'ca',
      name: 'Scholarships for the Canadian Students',
      country: 'Canada',
      region: CommunityRegion.americas,
      members: 76,
      online: 24,
      bio:
          'Welcome Scholarships for the Canadian Students. Vanier, CGA and university-specific awards.',
      bannerGradient: [
        Color(0xFFD52B1E),
        Color(0xFFFF6B6B),
      ],
      flagEmoji: '🇨🇦',
      hashtag: '#CAScholars',
      initials: 'CA',
    ),
    CommunityGroup(
      id: 'br',
      name: 'Scholarships for the Brazilian Students',
      country: 'Brazil',
      region: CommunityRegion.americas,
      members: 44,
      online: 13,
      bio:
          'Welcome Scholarships for the Brazilian Students. Ciencia sem Fronteiras, CAPES and CNPq.',
      bannerGradient: [
        Color(0xFF009C3B),
        Color(0xFFFFDF00),
      ],
      flagEmoji: '🇧🇷',
      hashtag: '#BRScholars',
      initials: 'BR',
    ),

    // Oceania
    CommunityGroup(
      id: 'au',
      name: 'Scholarships for the Australian Students',
      country: 'Australia',
      region: CommunityRegion.oceania,
      members: 68,
      online: 20,
      bio:
          'Welcome Scholarships for the Australian Students. RTP, Australia Awards and university excellence.',
      bannerGradient: [
        Color(0xFF012169),
        Color(0xFFE4002B),
      ],
      flagEmoji: '🇦🇺',
      hashtag: '#AUScholars',
      initials: 'AU',
    ),
    CommunityGroup(
      id: 'nz',
      name: 'Scholarships for the New Zealand Students',
      country: 'New Zealand',
      region: CommunityRegion.oceania,
      members: 36,
      online: 8,
      bio:
          'Welcome Scholarships for the New Zealand Students. NZ Scholarship, Manaaki and university awards.',
      bannerGradient: [
        Color(0xFF012169),
        Color(0xFF4FB6E0),
      ],
      flagEmoji: '🇳🇿',
      hashtag: '#NZScholars',
      initials: 'NZ',
    ),

    // Middle East
    CommunityGroup(
      id: 'sa',
      name: 'Scholarships for the Saudi Arabian Students',
      country: 'Saudi Arabia',
      region: CommunityRegion.middleEast,
      members: 49,
      online: 16,
      bio:
          'Welcome Scholarships for the Saudi Arabian Students. CSCEC Saudi, King Abdullah and abroad programs.',
      bannerGradient: [
        Color(0xFF006C35),
        Color(0xFF34A853),
      ],
      flagEmoji: '🇸🇦',
      hashtag: '#SAScholars',
      initials: 'SA',
    ),
    CommunityGroup(
      id: 'ae',
      name: 'Scholarships for the Emirati Students',
      country: 'United Arab Emirates',
      region: CommunityRegion.middleEast,
      members: 32,
      online: 7,
      bio:
          'Welcome Scholarships for the Emirati Students. Ministry of Education and global fellowships.',
      bannerGradient: [
        Color(0xFF00732F),
        Color(0xFFFF0000),
      ],
      flagEmoji: '🇦🇪',
      hashtag: '#AEScholars',
      initials: 'AE',
    ),
  ];
}