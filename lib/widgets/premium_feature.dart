/// Catalog of premium-only features surfaced across the ScholarBird app.
///
/// Each entry drives both the in-app upgrade dialog (so free users
/// understand what they unlock) and the analytics / permissions story.
///
/// The list intentionally mirrors the 7 features locked in the original
/// brief so the design and product teams can iterate without code edits
/// for every new feature.
library;

import 'package:flutter/material.dart';

/// Identifier for every premium-gated surface in the app.
enum PremiumFeature {
  aiRecommendations(
    title: 'AI-Powered Recommendations',
    description:
        'Get personalised scholarship matches ranked by your profile strength.',
    icon: Icons.auto_awesome,
  ),
  sopGenerator(
    title: 'SOP Generator',
    description:
        'Draft a tailored Statement of Purpose from your profile, documents and references.',
    icon: Icons.edit_document,
  ),
  aiChatAssistant(
    title: 'AI Chat Assistant',
    description:
        'Chat with ScholarBird AI for instant guidance on scholarships, SOPs, visas and more.',
    icon: Icons.chat_bubble_outline_rounded,
  ),
  cvGenerator(
    title: 'CV Generator',
    description:
        'Build a polished academic CV from your profile in one tap.',
    icon: Icons.description_outlined,
  ),
  premiumFilters(
    title: 'Premium Filters',
    description:
        'Unlock advanced filters — deadline window, IELTS band, funding type and more.',
    icon: Icons.tune,
  ),
  unlimitedSavedScholarships(
    title: 'Unlimited Saved Scholarships',
    description:
        'Save unlimited scholarships and access them from any device.',
    icon: Icons.bookmark_outline,
  ),
  premiumBadge(
    title: 'Premium Badge',
    description:
        'Stand out with a verified ScholarBird Pro badge on your profile.',
    icon: Icons.workspace_premium,
  );

  const PremiumFeature({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}