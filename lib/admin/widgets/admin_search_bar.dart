/// Reusable search input styled to match the ScholarBird theme.
library;

import 'package:flutter/material.dart';

class AdminSearchBar extends StatefulWidget {
  const AdminSearchBar({
    super.key,
    required this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onFilterTap,
    this.filterMenuBuilder,
    this.hasActiveFilters = false,
    this.hintText = 'SearchÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦',
    this.controller,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Called when the user taps the clear icon. Defaults to clearing
  /// the controller and forwarding an empty string to [onChanged] if
  /// no callback is provided.
  final VoidCallback? onClear;
  final VoidCallback? onFilterTap;
  final PopupMenuItemBuilder<void>? filterMenuBuilder;
  final bool hasActiveFilters;
  final String hintText;
  final TextEditingController? controller;

  @override
  State<AdminSearchBar> createState() => _AdminSearchBarState();
}

class _AdminSearchBarState extends State<AdminSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: (_controller.text.isEmpty &&
                    widget.onFilterTap == null &&
                    widget.filterMenuBuilder == null)
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _controller.clear();
                            if (widget.onClear != null) {
                              widget.onClear!();
                            } else {
                              widget.onChanged('');
                            }
                          },
                        ),
                      if (widget.filterMenuBuilder != null)
                        PopupMenuButton<void>(
                          tooltip: 'Filters',
                          icon: const Icon(Icons.tune_rounded),
                          itemBuilder: widget.filterMenuBuilder!,
                        )
                      else if (widget.onFilterTap != null)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.tune_rounded),
                              tooltip: 'Filters',
                              onPressed: widget.onFilterTap,
                            ),
                            if (widget.hasActiveFilters)
                              const Positioned(
                                right: 9,
                                top: 9,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF5B7AE8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(width: 7, height: 7),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      );
}
