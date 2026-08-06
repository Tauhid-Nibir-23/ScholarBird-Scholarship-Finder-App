import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

const sbBlue = Color(0xFF5B7AE8);
const sbInk = Color(0xFF1A1A2E);

/// Returns true when [value] is null, empty, or whitespace-only.
///
/// Centralises the "no image" guard so callers never have to remember
/// to strip + null-check. Keeps the rule consistent across all
/// ScholarshipImage consumers and prevents `CachedNetworkImage` from
/// ever being constructed with an empty string URL.
bool _isMissingImage(String? value) {
  if (value == null) return true;
  final trimmed = value.trim();
  return trimmed.isEmpty;
}

class ScholarshipImage extends StatelessWidget {
  const ScholarshipImage(
      {required this.url, required this.height, super.key, this.heroTag, this.country});
  final String? url;
  final double height;
  final String? heroTag;
  final String? country;

  @override
  Widget build(BuildContext context) {
    final hasImage = !_isMissingImage(url);
    final clip = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: url!.trim(),
                width: double.infinity,
                height: height,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, __) => const _ImagePlaceholder(),
                errorWidget: (_, __, ___) => _AssetFallbackImage(country: country),
              )
            : _AssetFallbackImage(country: country),
      ),
    );
    return heroTag == null || !hasImage
        ? clip
        : Hero(tag: heroTag!, child: clip);
  }
}

class _AssetFallbackImage extends StatelessWidget {
  const _AssetFallbackImage({this.country});
  final String? country;

  String get _countryAsset {
    final normalized = country?.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'assets/images/defaults/${normalized ?? ''}.jpg';
  }

  @override
  Widget build(BuildContext context) => Image.asset(
        _countryAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/defaults/default.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
        ),
      );
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8EDFF), Color(0xFFF4F6FF)],
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: sbBlue.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined,
              color: sbBlue,
              size: 32,
              semanticLabel: 'Scholarship image placeholder'),
        ),
      );
}

class ScholarshipSkeletonList extends StatelessWidget {
  const ScholarshipSkeletonList({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const _SkeletonCard(),
      );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) => Container(
        height: 290,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            _ShimmerBar(height: 140),
            Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBar(width: 210, height: 18),
                  SizedBox(height: 12),
                  _ShimmerBar(width: 150, height: 12),
                  SizedBox(height: 18),
                  _ShimmerBar(height: 12),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({required this.height, this.width = double.infinity});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
          color: const Color(0xFFE9EDF5),
          borderRadius: BorderRadius.circular(8)));
}

class ScholarshipState extends StatelessWidget {
  const ScholarshipState(
      {required this.icon,
      required this.title,
      required this.description,
      super.key,
      this.onRetry});
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
          child: Semantics(
        liveRegion: true,
        label: '$title. $description',
        child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                      color: Color(0xFFE8EDFF), shape: BoxShape.circle),
                  child: Icon(icon, color: sbBlue, size: 42)),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: sbInk, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(description,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFF667085), height: 1.45)),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again')))
              ],
            ])),
      ));
}

class InfoPill extends StatelessWidget {
  const InfoPill(
      {required this.label,
      required this.icon,
      super.key,
      this.color = sbBlue});
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w700)))
      ]));
}
