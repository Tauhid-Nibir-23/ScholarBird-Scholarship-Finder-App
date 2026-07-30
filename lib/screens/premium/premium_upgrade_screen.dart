import 'package:flutter/material.dart';

/// Displays the benefits of Pro. Subscription state must be changed only by a
/// verified server-side payment flow, not from this client screen.
class PremiumUpgradeScreen extends StatelessWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F7FB),
          elevation: 0,
          title: const Text('ScholarBird Pro'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B7AE8), Color(0xFF7B61FF)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.workspace_premium, color: Colors.white, size: 40),
                      SizedBox(height: 16),
                      Text('ScholarBird Pro',
                          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                      SizedBox(height: 8),
                      Text('Unlock every tool you need for stronger applications.',
                          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Text('What you get',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 14),
                const _Benefit(icon: Icons.send_outlined, text: 'Apply to scholarships'),
                const _Benefit(icon: Icons.auto_awesome_outlined, text: 'AI scholarship advisor'),
                const _Benefit(icon: Icons.description_outlined, text: 'SOP assistance'),
                const _Benefit(icon: Icons.badge_outlined, text: 'Resume guidance'),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Connect your payment provider to activate ScholarBird Pro.')),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B7AE8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Upgrade to Pro',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                const Text('Subscription activation is handled securely by the payment service.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6B7A95))),
              ],
            ),
          ),
        ),
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          const Icon(Icons.check_circle, color: Color(0xFF5B7AE8), size: 20),
          const SizedBox(width: 12),
          Icon(icon, size: 20, color: const Color(0xFF5B7AE8)),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        ]),
      );
}
