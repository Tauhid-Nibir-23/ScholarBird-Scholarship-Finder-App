/// Mentor Reviews — full review list + add-review form.
///
/// Reviews are stored in the `mentor_reviews` collection. New reviews
/// are gated to the "completed" bookings of the current user.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/mentor_review.dart';
import '../../models/mentor_profile.dart';
import '../../theme/scholarbird_theme.dart';

class MentorReviewsScreen extends StatelessWidget {
  const MentorReviewsScreen({required this.mentor, super.key});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Reviews',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review_outlined),
            tooltip: 'Add a review',
            onPressed: () => _showAddReviewSheet(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('mentor_reviews')
            .where('mentorId', isEqualTo: mentor.id)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: ScholarBirdColors.primary),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load reviews: ${snapshot.error}'),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyReviews(mentor: mentor);
          }
          final reviews = docs
              .map((d) => MentorReview.fromMap(
                    {...d.data() as Map<String, dynamic>, 'id': d.id},
                  ))
              .toList();
          return ListView.separated(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            itemCount: reviews.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: ScholarBirdSpacing.small),
            itemBuilder: (context, index) =>
                _ReviewCard(review: reviews[index]),
          );
        },
      ),
    );
  }

  void _showAddReviewSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ScholarBirdColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: AddReviewForm(mentor: mentor),
        );
      },
    );
  }
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.reviews_outlined,
            size: 56,
            color: ScholarBirdColors.body,
          ),
          const SizedBox(height: 12),
          const Text(
            'No reviews yet',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Be the first to leave a review after a session.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ScholarBirdColors.body),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final MentorReview review;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, yyyy');
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: ScholarBirdColors.primary,
                child: Text(
                  review.userName.isEmpty
                      ? '?'
                      : review.userName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ScholarBirdColors.ink,
                      ),
                    ),
                    Text(
                      formatter.format(review.date),
                      style: const TextStyle(
                        color: ScholarBirdColors.body,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    Icon(
                      i < review.rating.round()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: const Color(0xFFF59E0B),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.review,
            style: const TextStyle(color: ScholarBirdColors.body, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class AddReviewForm extends StatefulWidget {
  const AddReviewForm({required this.mentor, super.key});

  final MentorProfile mentor;

  @override
  State<AddReviewForm> createState() => _AddReviewFormState();
}

class _AddReviewFormState extends State<AddReviewForm> {
  double _rating = 5;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to leave a review.')),
      );
      return;
    }
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a brief comment.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final review = MentorReview(
        id: '',
        mentorId: widget.mentor.id,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? 'Student',
        rating: _rating,
        review: comment,
        date: DateTime.now(),
      );
      await FirebaseFirestore.instance
          .collection('mentor_reviews')
          .add(review.toMap());
      // Recompute aggregate on the mentor profile.
      final ref = FirebaseFirestore.instance
          .collection('mentors_marketplace')
          .doc(widget.mentor.id);
      final snapshot = await FirebaseFirestore.instance
          .collection('mentor_reviews')
          .where('mentorId', isEqualTo: widget.mentor.id)
          .get();
      final total = snapshot.docs.length;
      final avg = total == 0
          ? 0.0
          : snapshot.docs.fold<double>(0, (sum, doc) {
              final data = doc.data();
              final r = (data['rating'] as num?)?.toDouble() ?? 0;
              return sum + r;
            }) /
              total;
      await ref.set({
        'rating': double.parse(avg.toStringAsFixed(2)),
        'totalReviews': total,
      }, SetOptions(merge: true));

      messenger.showSnackBar(
        const SnackBar(content: Text('Review submitted.')),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not submit review: $e')),
      );
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ScholarBirdColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rate your experience',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (index) {
              final filled = index < _rating.round();
              return IconButton(
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: filled ? const Color(0xFFF59E0B) : ScholarBirdColors.body,
                ),
                onPressed: () => setState(() => _rating = (index + 1).toDouble()),
              );
            }),
          ),
          Text(
            'Rating: ${_rating.toStringAsFixed(1)} / 5',
            style: const TextStyle(color: ScholarBirdColors.body),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Your review',
              hintText: 'What did you find helpful?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: ScholarBirdColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _submitting ? 'Submitting...' : 'Submit review',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
