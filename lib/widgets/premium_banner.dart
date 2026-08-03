import 'package:flutter/material.dart';
import '../models/subscription_model.dart';

class PremiumBanner extends StatelessWidget {
  const PremiumBanner(
      {required this.subscription, required this.onTap, super.key});
  final SubscriptionModel subscription;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = subscription.isPremium;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)]),
          borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.workspace_premium, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(active ? 'ScholarBird Pro Activated' : 'Unlock ScholarBird Pro',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
              active
                  ? 'Subscription active - ${subscription.daysRemaining} days remaining'
                  : 'Unlock scholarship applications and premium benefits.',
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12)),
          const SizedBox(height: 10),
          Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Text(active ? 'View Details' : 'Upgrade Now',
                          style: const TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)))))
        ]))
      ]),
    );
  }
}
