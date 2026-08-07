import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Home-page preview of the upcoming ScholarBird community.
class HomeCommunityFeed extends StatelessWidget {
  const HomeCommunityFeed({super.key});

  static const _blue = AppColors.primary;
  static const _ink = AppColors.textPrimary;
  static const _muted = AppColors.textSecondary;
  static const _fallback = <Map<String, dynamic>>[
    {
      'authorName': 'Nusrat Jahan',
      'authorRole': 'Verified Mentor',
      'title': 'Erasmus Mundus 2027: preparation checklist',
      'content':
          'Start your CV, recommendation letters and programme shortlist now. I have added the steps that helped my last batch.',
      'likes': 24,
      'comments': 8,
      'accent': 0xFF10B981,
    },
    {
      'authorName': 'ScholarBird Team',
      'authorRole': 'Official update',
      'title': 'New fully funded opportunities have been verified',
      'content':
          'Our team has reviewed new scholarships and refreshed their deadlines. Explore them before you apply.',
      'likes': 38,
      'comments': 11,
      'accent': 0xFF1E54FF,
    },
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('ScholarBird Community',
                      style: TextStyle(
                          fontFamily: AppText.fontFamily,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2)),
                  SizedBox(height: 3),
                  Text('Learn from scholars, mentors and alumni.',
                      style: TextStyle(
                          fontFamily: AppText.fontFamily,
                          fontSize: 13,
                          color: _muted)),
                ])),
            TextButton.icon(
                onPressed: () => _notice(context),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('View all',
                    style: TextStyle(
                        fontFamily: AppText.fontFamily,
                        fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary)),
          ]),
          const SizedBox(height: 14),
          const _Composer(),
          const SizedBox(height: 12),
          const _Topics(),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('community_posts')
                .orderBy('createdAt', descending: true)
                .limit(2)
                .snapshots(),
            builder: (context, snapshot) {
              final posts = snapshot.hasData && snapshot.data!.docs.isNotEmpty
                  ? snapshot.data!.docs
                      .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
                      .toList(growable: false)
                  : _fallback;
              return Column(children: [
                for (var i = 0; i < posts.length; i++) ...[
                  _Post(post: posts[i]),
                  if (i < posts.length - 1) const SizedBox(height: 12),
                ]
              ]);
            },
          ),
        ]),
      );

  static void _notice(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Community posting will be available in the next update.')),
      );
}

class _Composer extends StatelessWidget {
  const _Composer();

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    // Only admins and moderators can publish posts; everyone else gets a
    // read-only notice that explains they can react/comment instead.
    if (currentUser == null) {
      return _ViewerOnlyNotice(
        message:
            'Sign in to react and comment on community posts.',
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final role = _resolveRole(snapshot.data?.data());
        if (!_canPost(role)) {
          return _ViewerOnlyNotice(
            message:
                'Only ScholarBird admins and moderators can post. '
                'React and join the conversation below.',
          );
        }
        return _ComposerCard(
          onTap: () => HomeCommunityFeed._notice(context),
        );
      },
    );
  }
}

String? _resolveRole(Map<String, dynamic>? data) {
  if (data == null) return null;
  final direct = data['role'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  final admin = data['isAdmin'];
  if (admin == true) return 'admin';
  final moderator = data['isModerator'];
  if (moderator == true) return 'moderator';
  return null;
}

bool _canPost(String? role) {
  if (role == null) return false;
  final normalized = role.toLowerCase();
  return normalized == 'admin' || normalized == 'moderator';
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.innerSoft),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_note_rounded,
                      color: HomeCommunityFeed._blue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text(
                        'Share an update with the community…',
                        style: TextStyle(
                            fontFamily: AppText.fontFamily,
                            color: HomeCommunityFeed._muted,
                            fontSize: 13))),
                const Icon(Icons.add_circle_outline_rounded,
                    color: HomeCommunityFeed._blue),
              ]),
            )),
      );
}

class _ViewerOnlyNotice extends StatelessWidget {
  const _ViewerOnlyNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primarySoft.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          const Icon(Icons.forum_rounded,
              color: HomeCommunityFeed._blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: AppText.fontFamily,
                fontSize: 12.5,
                height: 1.4,
                color: HomeCommunityFeed._ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      );
}

class _Topics extends StatelessWidget {
  const _Topics();
  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _Topic('For you', selected: true),
        _Topic('Scholarships', selected: false),
        _Topic('Visa journey', selected: false),
        _Topic('SOP & CV', selected: false),
      ]));
}

class _Topic extends StatelessWidget {
  const _Topic(this.label, {required this.selected});
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected
              ? AppGradients.primary
              : const LinearGradient(
                  colors: [Color(0xFFF4F7FC), Color(0xFFF4F7FC)],
                ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.cardBorder),
          boxShadow: selected ? AppShadows.innerSoft : null,
        ),
        child: Text(
          label,
          style: TextStyle(
              fontFamily: AppText.fontFamily,
              color: selected ? Colors.white : HomeCommunityFeed._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700),
        ),
      ));
}

class _Post extends StatelessWidget {
  const _Post({required this.post});
  final Map<String, dynamic> post;
  @override
  Widget build(BuildContext context) {
    final role =
        (post['authorRole'] ?? post['role'] ?? 'Community member').toString();
    final title = (post['title'] ?? '').toString();
    final content = (post['content'] ?? post['body'] ?? '').toString();
    final accent = Color((post['accent'] as int?) ??
        (role.toLowerCase().contains('mentor')
            ? 0xFF10B981
            : 0xFF1E54FF));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.soft,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
                role.toLowerCase().contains('mentor')
                    ? Icons.school_rounded
                    : Icons.campaign_rounded,
                color: accent,
                size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text((post['authorName'] ?? 'ScholarBird Community').toString(),
                    style: const TextStyle(
                        fontFamily: AppText.fontFamily,
                        fontWeight: FontWeight.w800,
                        color: HomeCommunityFeed._ink)),
                Text(role,
                    style: TextStyle(
                        fontFamily: AppText.fontFamily,
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w700)),
              ])),
          const Icon(Icons.more_horiz_rounded,
              color: HomeCommunityFeed._muted),
        ]),
        const SizedBox(height: 14),
        if (title.isNotEmpty)
          Text(title,
              style: const TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: HomeCommunityFeed._ink,
                  letterSpacing: -0.1)),
        if (title.isNotEmpty) const SizedBox(height: 6),
        Text(content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: AppText.fontFamily,
                fontSize: 13,
                height: 1.45,
                color: HomeCommunityFeed._muted)),
        const SizedBox(height: 13),
        Row(children: [
          _Action(
              icon: Icons.favorite_border_rounded,
              value: '${post['likes'] ?? 0}'),
          const SizedBox(width: 18),
          _Action(
              icon: Icons.chat_bubble_outline_rounded,
              value: '${post['comments'] ?? 0}'),
          const Spacer(),
          const Icon(Icons.share_outlined,
              size: 19, color: HomeCommunityFeed._muted),
        ]),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.value});
  final IconData icon;
  final String value;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: HomeCommunityFeed._muted),
        const SizedBox(width: 5),
        Text(value,
            style: const TextStyle(
                fontFamily: AppText.fontFamily,
                fontSize: 12,
                color: HomeCommunityFeed._muted,
                fontWeight: FontWeight.w600)),
      ]);
}
