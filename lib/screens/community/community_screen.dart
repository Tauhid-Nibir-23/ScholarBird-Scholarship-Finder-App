/// Community tab — country-based scholarship communities.
///
/// Layout (top → bottom):
///   1. Header (menu icon, "Community" title, subtitle, notification bell)
///   2. Search field
///   3. "Recommended for you" section heading
///   4. Vertical list of country cards
///
/// Uses a plain Column + SingleChildScrollView (no custom scrolls /
/// slivers) so the body always renders inside the host Scaffold.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'community_detail_screen.dart';
import 'community_models.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    this.onMenuTap,
    this.currentUserRole,
  });

  final VoidCallback? onMenuTap;

  /// Role of the signed-in user used to gate posting on the detail page.
  /// Accepted values: `'admin'`, `'moderator'`, `'mentor'`, or anything else
  /// (treated as a regular student with read-only access).
  final String? currentUserRole;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  final Set<String> _joined = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _onSearchChanged('');
  }

  List<CommunityGroup> get _visibleGroups {
    if (_query.isEmpty) return CommunityGroup.all;
    return CommunityGroup.all.where((g) {
      return g.name.toLowerCase().contains(_query) ||
          g.country.toLowerCase().contains(_query) ||
          g.hashtag.toLowerCase().contains(_query);
    }).toList();
  }

  void _toggleJoin(CommunityGroup group) {
    setState(() {
      if (_joined.contains(group.id)) {
        _joined.remove(group.id);
      } else {
        _joined.add(group.id);
      }
    });
    final joined = _joined.contains(group.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: joined ? AppColors.success : AppColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          content: Text(
            joined
                ? 'You joined ${group.country} community'
                : 'You left ${group.country} community',
            style: AppText.body.copyWith(color: Colors.white),
          ),
        ),
      );
  }

  void _openDetail(CommunityGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(
          group: group,
          currentUserRole: widget.currentUserRole,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleGroups;
    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onMenuTap: widget.onMenuTap),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: _SearchField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: _onSearchChanged,
                        onClear: _clearSearch,
                      ),
                    ),
                    if (CommunityGroup.featured.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: _FeaturedCarousel(
                          groups: CommunityGroup.featured,
                          isJoined: _joined.contains,
                          onJoin: _toggleJoin,
                          onTap: _openDetail,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _AllCommunitiesHeader(count: visible.length),
                    ),
                    if (visible.isEmpty)
                      const _EmptyState()
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            for (var i = 0; i < visible.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: i == visible.length - 1 ? 0 : 12,
                                ),
                                child: _CommunityRow(
                                  group: visible[i],
                                  isJoined: _joined.contains(visible[i].id),
                                  onJoin: () => _toggleJoin(visible[i]),
                                  onTap: () => _openDetail(visible[i]),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({this.onMenuTap});

  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CircleIconButton(
            icon: Icons.menu_rounded,
            onTap: onMenuTap,
            tooltip: 'Menu',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Community',
                  style: AppText.display.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 2),
                Text(
                  'Connect, share and grow with fellow scholars',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _NotificationBell(),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _CircleIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: () {},
          tooltip: 'Notifications',
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppShadows.innerSoft,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: AppText.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search groups, topics or tags',
                hintStyle: AppText.body.copyWith(
                  color: AppColors.textMuted,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Featured carousel + All Communities header
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({
    required this.groups,
    required this.isJoined,
    required this.onJoin,
    required this.onTap,
  });

  final List<CommunityGroup> groups;
  final bool Function(String id) isJoined;
  final ValueChanged<CommunityGroup> onJoin;
  final ValueChanged<CommunityGroup> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Featured for you',
                  style: TextStyle(
                    fontFamily: AppText.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _PillBadge(label: 'Top picks'),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final g = groups[i];
              return SizedBox(
                width: 220,
                child: _FeaturedCard(
                  group: g,
                  isJoined: isJoined(g.id),
                  onJoin: () => onJoin(g),
                  onTap: () => onTap(g),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: 0.2,
          ),
        ),
      );
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.group,
    required this.isJoined,
    required this.onJoin,
    required this.onTap,
  });

  final CommunityGroup group;
  final bool isJoined;
  final VoidCallback onJoin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: group.bannerGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.medium,
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FlagCircle(emoji: group.flagEmoji, size: 38),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${group.online} online',
                          style: const TextStyle(
                            fontFamily: AppText.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                group.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${group.members} members',
                style: TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  _FeaturedJoinPill(isJoined: isJoined, onPressed: onJoin),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedJoinPill extends StatelessWidget {
  const _FeaturedJoinPill({
    required this.isJoined,
    required this.onPressed,
  });

  final bool isJoined;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isJoined
                      ? Icons.check_rounded
                      : Icons.person_add_alt_1_rounded,
                  size: 14,
                  color: isJoined ? AppColors.success : AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  isJoined ? 'Joined' : 'Join',
                  style: TextStyle(
                    fontFamily: AppText.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isJoined ? AppColors.success : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _AllCommunitiesHeader extends StatelessWidget {
  const _AllCommunitiesHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'All Communities',
            style: TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Text(
              '$count groups',
              style: const TextStyle(
                fontFamily: AppText.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Country row card
// ─────────────────────────────────────────────────────────────────────────────

class _CommunityRow extends StatelessWidget {
  const _CommunityRow({
    required this.group,
    required this.isJoined,
    required this.onJoin,
    required this.onTap,
  });

  final CommunityGroup group;
  final bool isJoined;
  final VoidCallback onJoin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppShadows.innerSoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FlagCircle(emoji: group.flagEmoji, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: AppText.title.copyWith(fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${group.members} members',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _JoinPill(isJoined: isJoined, onPressed: onJoin),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                group.bio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MemberStack(seed: group.id),
                  const Spacer(),
                  Text(
                    group.hashtag,
                    style: AppText.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagCircle extends StatelessWidget {
  const _FlagCircle({required this.emoji, this.size = 40});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: AppShadows.innerSoft,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}

class _JoinPill extends StatelessWidget {
  const _JoinPill({required this.isJoined, required this.onPressed});

  final bool isJoined;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isJoined ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                isJoined ? 'Joined' : 'Join',
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deterministic mock member stack — three colored initial avatars + "+N".
class _MemberStack extends StatelessWidget {
  const _MemberStack({required this.seed});

  final String seed;

  static const _palette = <Color>[
    Color(0xFF1E54FF),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final codes = seed.codeUnits;
    int byteAt(int i) => i < codes.length ? codes[i] : i;
    final initials = <_AvatarSpec>[
      _AvatarSpec(_palette[byteAt(0) % _palette.length], 'K'),
      _AvatarSpec(_palette[byteAt(1) % _palette.length], 'K'),
      _AvatarSpec(_palette[byteAt(2) % _palette.length], 'K'),
    ];
    final overflow = 12 + (codes.length % 9);
    return SizedBox(
      height: 26,
      width: 26.0 + (initials.length - 1) * 16 + 30,
      child: Stack(
        children: [
          for (var i = 0; i < initials.length; i++)
            Positioned(
              left: i * 16.0,
              child: _AvatarBubble(spec: initials[i]),
            ),
          Positioned(
            left: initials.length * 16.0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$overflow',
                style: AppText.caption.copyWith(
                  color: AppColors.primary,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarSpec {
  const _AvatarSpec(this.color, this.initial);
  final Color color;
  final String initial;
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.spec});
  final _AvatarSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: spec.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        spec.initial,
        style: AppText.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.search_off_rounded,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No communities match your search',
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different keyword, region or tag.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
        ],
      ),
    );
  }
}
