/// Mentor Booking — package selection + request creation.
///
/// Records a `MentorBooking` document (status: `pendingPayment`) and
/// shows a placeholder "Continue to payment" button. The Payment gateway
/// is intentionally NOT wired — per the spec, scholarships already have
/// an isolated Payment Service and we want to keep mentor bookings
/// out of that pipeline.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/mentor_booking.dart';
import '../../models/mentor_package.dart';
import '../../models/mentor_profile.dart';
import '../../theme/scholarbird_theme.dart';

class MentorBookingScreen extends StatefulWidget {
  const MentorBookingScreen({required this.mentor, super.key});

  final MentorProfile mentor;

  @override
  State<MentorBookingScreen> createState() => _MentorBookingScreenState();
}

class _MentorBookingScreenState extends State<MentorBookingScreen> {
  late final List<MentorPackage> _packages;
  MentorPackage? _selected;
  bool _submitting = false;

  static const String _collectionName = 'mentor_bookings';

  @override
  void initState() {
    super.initState();
    _packages = defaultMentorPackages(widget.mentor.id);
    _selected = _packages.firstWhere(
      (p) => p.highlight,
      orElse: () => _packages.first,
    );
  }

  Future<void> _bookSession() async {
    if (_selected == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to book a mentor.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final booking = MentorBooking(
        id: '',
        mentorId: widget.mentor.id,
        mentorName: widget.mentor.name,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? 'Student',
        packageId: _selected!.id,
        packageName: _selected!.name,
        price: _selected!.price,
        currency: _selected!.currency,
        status: MentorBookingStatus.pendingPayment,
        createdAt: DateTime.now(),
        notes: '',
        durationMinutes: _selected!.durationMinutes,
      );
      final doc = await FirebaseFirestore.instance
          .collection(_collectionName)
          .add(booking.toMap());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Booking request created (${doc.id}). Proceed to payment.',
          ),
        ),
      );
      if (mounted) {
        setState(() => _submitting = false);
        _showPaymentSheet(booking);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create booking: $e')),
      );
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showPaymentSheet(MentorBooking booking) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ScholarBirdColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Booking request sent',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ScholarBirdColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your mentor booking request has been recorded with status '
                '“Awaiting payment”. The mentor will follow up directly to '
                'confirm the slot and arrange payment. You can also reach '
                'them via the WhatsApp or email details on the mentor page.',
                style: TextStyle(
                  color: ScholarBirdColors.body,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ScholarBirdColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = _selected?.currency ?? widget.mentor.currency;
    final formatter = NumberFormat.currency(
      symbol: currency.isEmpty ? '\$' : currency,
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Book Mentor',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
        children: [
          Container(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            decoration: BoxDecoration(
              color: ScholarBirdColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ScholarBirdColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: ScholarBirdColors.primary,
                  backgroundImage:
                      widget.mentor.profilePhoto?.isNotEmpty == true
                          ? NetworkImage(widget.mentor.profilePhoto!)
                          : null,
                  child: widget.mentor.profilePhoto?.isEmpty != false
                      ? Text(
                          widget.mentor.name.isEmpty
                              ? '?'
                              : widget.mentor.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.mentor.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ScholarBirdColors.ink,
                        ),
                      ),
                      Text(
                        widget.mentor.designation,
                        style: const TextStyle(
                          color: ScholarBirdColors.body,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          const Text(
            'Pick a package',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final pkg in _packages)
            _PackageTile(
              package: pkg,
              selected: _selected?.id == pkg.id,
              onTap: () => setState(() => _selected = pkg),
            ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          Container(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            decoration: BoxDecoration(
              color: ScholarBirdColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ScholarBirdColors.border),
            ),
            child: Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ScholarBirdColors.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  formatter.format(_selected?.price ?? 0),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: ScholarBirdColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _bookSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: ScholarBirdColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.calendar_month_rounded),
            label: Text(
              _submitting ? 'Saving...' : 'Continue to payment',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'You will not be charged until the mentor confirms your booking.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ScholarBirdColors.body, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final MentorPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      symbol: package.currency.isEmpty ? '\$' : package.currency,
      decimalDigits: 0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
          decoration: BoxDecoration(
            color: selected
                ? ScholarBirdColors.primary.withValues(alpha: .05)
                : ScholarBirdColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? ScholarBirdColors.primary
                  : ScholarBirdColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: ScholarBirdColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            package.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ScholarBirdColors.ink,
                            ),
                          ),
                        ),
                        if (package.highlight)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Popular',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package.description,
                      style: const TextStyle(
                        color: ScholarBirdColors.body,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: ScholarBirdColors.body,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          package.durationLabel,
                          style: const TextStyle(
                            color: ScholarBirdColors.body,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatter.format(package.price),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ScholarBirdColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
