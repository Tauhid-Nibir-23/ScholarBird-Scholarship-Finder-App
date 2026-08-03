import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/profile/profile_widgets.dart';
import 'saved_scholarship_controls.dart';

class SavedScholarshipCard extends StatelessWidget {
  const SavedScholarshipCard({
    required this.data,
    required this.onTap,
    super.key,
    this.onLongPress,
    this.isSelected = false,
    this.selectionMode = false,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Scholarship').toString();
    final country = (data['country'] ?? '').toString();
    final degree = (data['degree'] ?? '').toString();
    final savedAt = data['savedAt'];
    final imageUrl = (data['imageUrl'] ?? data['image'] ?? '').toString();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: selectionMode ? () => onLongPress?.call() : onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isSelected ? sbPrimary : sbBorder,
                width: isSelected ? 1.4 : 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: imageUrl.isEmpty
                        ? Container(
                            color: sbPrimary.withValues(alpha: 0.08),
                            child: const Icon(Icons.school_outlined,
                                color: sbPrimary),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: sbPrimary.withValues(alpha: 0.08),
                              child: const Icon(Icons.school_outlined,
                                  color: sbPrimary),
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 12, right: 12, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: sbText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SavedScholarshipIconButton(
                              scholarship: data, iconSize: 20),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(country.isEmpty ? 'Global' : country,
                          style: const TextStyle(
                              fontSize: 12, color: sbSecondaryText)),
                      const SizedBox(height: 4),
                      Text(degree.isEmpty ? 'Degree not available' : degree,
                          style: const TextStyle(
                              fontSize: 12, color: sbSecondaryText)),
                      const SizedBox(height: 6),
                      Text(
                        savedAt is Timestamp
                            ? 'Saved ${savedAt.toDate().day}/${savedAt.toDate().month}/${savedAt.toDate().year}'
                            : 'Saved locally',
                        style: const TextStyle(
                            fontSize: 12, color: sbSecondaryText),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onTap,
                          child: const Text('View details'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
