/// Detail screen for a single [CommunityGroup].
///
/// Layout (top → bottom):
///   1. AppBar with title + overflow menu
///   2. Cover/gradient banner (180px) with overlapping flag avatar
///   3. Title block (name, public group · country, Joined pill)
///   4. Member row + Invite/Share buttons
///   5. About card with country tag + member row
///   6. Posts feed header
///   7. Post cards (avatar, name, role, time, content, action row)
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'community_models.dart';

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({
    required this.group,
    this.currentUserRole,
    super.key,
  });

  final CommunityGroup group;
  final String? currentUserRole;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final TextEditingController _composerCtrl = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final List<_Post> _userPosts = <_Post>[];

  bool get _canPost {
    final role = widget.currentUserRole?.toLowerCase();
    return role == 'admin' || role == 'moderator' || role == 'mentor';
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _submitPost() {
    final text = _composerCtrl.text.trim();
    if (text.isEmpty) return;
    final role = widget.currentUserRole ?? 'Member';
    final displayRole = role.toLowerCase() == 'admin'
        ? 'Admin · ${widget.group.country}'
        : role.toLowerCase() == 'moderator'
            ? 'Moderator · ${widget.group.country}'
            : 'Mentor · ${widget.group.country}';
    setState(() {
      _userPosts.insert(
        0,
        _Post(
          author: 'You',
          role: displayRole,
          isVerified: true,
          time: 'Just now',
          content: text,
          likes: 0,
          comments: 0,
          shares: 0,
        ),
      );
      _composerCtrl.clear();
    });
    _composerFocus.unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          content: Text(
            'Post published',
            style: AppText.body.copyWith(color: Colors.white),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final allPosts = [..._userPosts, ..._seedPosts()];
    final accent = widget.group.bannerGradient.first;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _CoverSliver(group: widget.group),
          SliverToBoxAdapter(
            child: _TitleBlock(group: widget.group),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _AboutCard(group: widget.group),
            ),
          ),
          if (_canPost)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _PostComposer(
                  controller: _composerCtrl,
                  focusNode: _composerFocus,
                  accent: accent,
                  role: widget.currentUserRole ?? 'mentor',
                  onSubmit: _submitPost,
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: Text(
                'Posts',
                style: TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PostCard(
                    post: allPosts[i],
                    accent: accent,
                  ),
                ),
                childCount: allPosts.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_Post> _seedPosts() => [
        _Post(
          author: 'Phoura V',
          role: 'Scholarbird Scholarship Mentor | UTokyo Alum',
          isVerified: true,
          time: '2 weeks ago',
          content:
              'Welcome to Scholarships for the Timor-Leste students. Feel free to post, share or comments on the relevant contents.',
          likes: 1,
          comments: 2,
          shares: 0,
        ),
        _Post(
          author: 'Aisha K.',
          role: 'Mentor · ${widget.group.country}',
          time: '2h ago',
          content:
              'New DAAD scholarship list just dropped! I\'ll share the full list below — deadlines are tight so apply early.',
          likes: 24,
          comments: 6,
          shares: 3,
        ),
        _Post(
          author: 'Rahim S.',
          role: 'Alumni · ${widget.group.country}',
          time: '6h ago',
          content:
              'Anyone preparing for IELTS next month? I have free templates for Writing Task 2 — DM me.',
          likes: 41,
          comments: 12,
          shares: 9,
        ),
        _Post(
          author: 'Lin T.',
          role: 'Member · ${widget.group.country}',
          time: '1d ago',
          content:
              'Visa interview tips from my Fulbright session. The trick is to keep your "study plan" concise.',
          likes: 18,
          comments: 4,
          shares: 2,
        ),
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Cover banner + AppBar
// ─────────────────────────────────────────────────────────────────────────────

class _CoverSliver extends StatelessWidget {
  const _CoverSliver({required this.group});
  final CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 200,
      collapsedHeight: kToolbarHeight,
      backgroundColor: group.bannerGradient.first,
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        group.name,
        style: const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () {},
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: _CoverBanner(group: group),
      ),
    );
  }
}

class _CoverBanner extends StatelessWidget {
  const _CoverBanner({required this.group});
  final CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient base
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: group.bannerGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Decorative glow circles (so it still looks like a "cover image")
        Positioned(
          top: -60,
          right: -40,
          child: _Bubble(
            size: 180,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        Positioned(
          bottom: -40,
          left: -60,
          child: _Bubble(
            size: 220,
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        Positioned(
          top: 40,
          right: 40,
          child: _Bubble(
            size: 90,
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        // Subtle dark overlay to keep text readable
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: 0.25),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Title block (below banner)
// ─────────────────────────────────────────────────────────────────────────────

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.group});
  final CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: const TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Public group',
                style: AppText.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              Text(
                '  ·  ',
                style: AppText.body.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
              Flexible(
                child: Text(
                  group.country,
                  style: AppText.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              const _JoinedPill(),
            ],
          ),
          const SizedBox(height: 14),
          // Member row + hashtag
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MemberStack(seed: group.id),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${group.members + 1} members joined',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            group.hashtag,
            style: AppText.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinedPill extends StatelessWidget {
  const _JoinedPill();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 14,
              color: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'Joined',
              style: AppText.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// About card
// ─────────────────────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.group});
  final CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            children: [
              const Text(
                'About',
                style: TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(
                    Icons.public_rounded,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    group.country,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Welcome ${group.name}',
            style: AppText.body,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MemberStack(seed: group.id),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${group.members + 1} members joined',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                group.country,
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member stack (4 avatars + N)
// ─────────────────────────────────────────────────────────────────────────────

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
    final avatars = <_AvatarSpec>[
      _AvatarSpec(_palette[byteAt(0) % _palette.length], 'A'),
      _AvatarSpec(_palette[byteAt(1) % _palette.length], 'K'),
      _AvatarSpec(_palette[byteAt(2) % _palette.length], 'S'),
      _AvatarSpec(_palette[byteAt(3) % _palette.length], 'M'),
    ];
    final overflow = 60 + (codes.length % 9);
    return SizedBox(
      height: 28,
      width: 28.0 + (avatars.length - 1) * 18 + 36,
      child: Stack(
        children: [
          for (var i = 0; i < avatars.length; i++)
            Positioned(
              left: i * 18.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: avatars[i].color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  avatars[i].initial,
                  style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          Positioned(
            left: avatars.length * 18.0,
            child: Container(
              width: 28,
              height: 28,
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
                  fontSize: 10,
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

// ─────────────────────────────────────────────────────────────────────────────
// Post composer (moderator / admin / mentor only)
// ─────────────────────────────────────────────────────────────────────────────

class _PostComposer extends StatelessWidget {
  const _PostComposer({
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.role,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final String role;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: AppShadows.innerSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Y',
                  style: AppText.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'You',
                          style: TextStyle(
                            fontFamily: AppText.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '·',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _roleLabel(role),
                            style: AppText.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Can post',
                  style: AppText.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 4,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            style: AppText.body.copyWith(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Share an update, scholarship tip or opportunity…',
              hintStyle: AppText.body.copyWith(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: accent, width: 1.2),
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.all(12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.image_outlined, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'Attach image',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.attach_file_rounded, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'Attach file',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.poll_outlined, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'Create poll',
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: onSubmit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.send_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Post',
                          style: TextStyle(
                            fontFamily: AppText.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    final r = role.toLowerCase();
    if (r == 'admin') return 'Admin';
    if (r == 'moderator') return 'Moderator';
    return 'Mentor';
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Posts feed
// ─────────────────────────────────────────────────────────────────────────────

class _Post {
  const _Post({
    required this.author,
    required this.role,
    required this.time,
    required this.content,
    required this.likes,
    required this.comments,
    required this.shares,
    this.isVerified = false,
  });

  final String author;
  final String role;
  final String time;
  final String content;
  final int likes;
  final int comments;
  final int shares;
  final bool isVerified;
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.accent});
  final _Post post;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  post.author.characters.first,
                  style: AppText.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.author,
                            style: AppText.label.copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (post.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ],
                        const SizedBox(width: 6),
                        const Text(
                          '·',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          post.role,
                          style: AppText.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      post.time,
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.more_horiz_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(post.content, style: AppText.body),
          const SizedBox(height: 12),
          Row(
            children: [
              _PostAction(
                icon: Icons.favorite_border_rounded,
                label: '${post.likes}',
              ),
              const SizedBox(width: 18),
              _PostAction(
                icon: Icons.mode_comment_outlined,
                label: '${post.comments}',
              ),
              const SizedBox(width: 18),
              _PostAction(
                icon: Icons.ios_share_rounded,
                label: '${post.shares}',
              ),
              const Spacer(),
              const Icon(
                Icons.bookmark_border_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
