import 'package:flutter/material.dart';

import '../screens/profile/profile_widgets.dart';

class SavedEmptyState extends StatelessWidget {
  const SavedEmptyState({required this.onBrowse, super.key});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: sbPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bookmark_border,
                    color: sbPrimary, size: 44),
              ),
              const SizedBox(height: 16),
              const Text(
                'No saved scholarships yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: sbText),
              ),
              const SizedBox(height: 8),
              const Text(
                'Saved scholarships will appear here for quick access, offline viewing, and later review.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sbSecondaryText, height: 1.45),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onBrowse,
                child: const Text('Browse Scholarships'),
              ),
            ],
          ),
        ),
      );
}
