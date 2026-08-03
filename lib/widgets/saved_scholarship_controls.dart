import 'package:flutter/material.dart';

import '../services/saved_scholarships_service.dart';

class SavedScholarshipIconButton extends StatelessWidget {
  const SavedScholarshipIconButton({
    required this.scholarship,
    super.key,
    this.iconSize = 24,
  });

  final Map<String, dynamic> scholarship;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scholarshipId = (scholarship['id'] ?? '').toString();
    if (scholarshipId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<bool>(
      stream: SavedScholarshipsService.instance.watchSavedStatus(scholarshipId),
      builder: (context, snapshot) {
        final isSaved = snapshot.data ?? false;
        return Semantics(
          button: true,
          label: isSaved ? 'Unsave scholarship' : 'Save scholarship',
          child: IconButton(
            tooltip: isSaved ? 'Saved' : 'Save',
            iconSize: iconSize,
            onPressed: () async {
              if (isSaved) {
                await SavedScholarshipsService.instance
                    .unsaveScholarship(scholarshipId);
              } else {
                await SavedScholarshipsService.instance
                    .saveScholarship(scholarship);
              }
            },
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
                child: child,
              ),
              child: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                key: ValueKey<bool>(isSaved),
                color: isSaved ? Colors.amber : const Color(0xFF6B7A95),
                size: iconSize,
              ),
            ),
          ),
        );
      },
    );
  }
}
