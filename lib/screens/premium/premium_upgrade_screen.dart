/// Subscription upgrade flow with one-tap local activation.
///
/// This screen intentionally does **not** contact any backend or payment
/// gateway (SSLCommerz, mock checkout, in-process direct-activate, etc.).
/// Tapping the "Upgrade to PRO" button flips the user to premium in
/// [SubscriptionProvider] for the selected plan's full duration, and the
/// state is mirrored to SharedPreferences so a reload keeps them premium.
import 'package:flutter/material.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription_provider.dart';
import '../../widgets/premium_guard.dart';

enum PaymentState {
  idle,
  activating,
  success,
  failed,
}

class PremiumUpgradeScreen extends StatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen> {
  SubscriptionPlan _selectedPlan = SubscriptionPlan.monthly;
  PaymentState _paymentState = PaymentState.idle;

  String? _statusMessage;
  String? _errorMessage;

  bool get _isProcessing => _paymentState == PaymentState.activating;

  Future<void> _handleUpgrade() async {
    if (_isProcessing) return;

    setState(() {
      _paymentState = PaymentState.activating;
      _statusMessage = 'Activating premium...';
      _errorMessage = null;
    });

    try {
      // Tiny artificial delay so the spinner is visible; the activation is
      // otherwise instant because it is purely local.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final provider = SubscriptionProviderScope.of(context);
      await provider.activateLocalDemo(plan: _selectedPlan);

      if (!mounted) return;
      setState(() {
        _paymentState = PaymentState.success;
        _statusMessage =
            'Premium activated for ${_selectedPlan.label}!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentState = PaymentState.failed;
        _errorMessage = 'Could not activate premium: ${e.toString()}';
      });
    }
  }

  void _resetFlow() {
    setState(() {
      _paymentState = PaymentState.idle;
      _statusMessage = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = SubscriptionProviderScope.of(context);
    final alreadyPremium = provider.isPremium;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FB),
        title: const Text('ScholarBird Pro'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ScholarBird PRO',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlock the complete scholarship experience',
                style: TextStyle(color: Color(0xFF6B7A95)),
              ),
              const SizedBox(height: 20),

              if (alreadyPremium && _paymentState != PaymentState.success)
                _buildAlreadyActiveCard(provider),
              if (_paymentState == PaymentState.success) _buildSuccessCard(),
              if (_paymentState == PaymentState.failed) _buildFailedCard(),

              if (_paymentState == PaymentState.idle || _isProcessing) ...[
                const Text(
                  'Select Subscription Plan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildPlanCard(
                      plan: SubscriptionPlan.monthly,
                      priceText: '৳299 / mo',
                      subtitle: '1 Month',
                    ),
                    const SizedBox(width: 8),
                    _buildPlanCard(
                      plan: SubscriptionPlan.sixMonths,
                      priceText: '৳1299',
                      subtitle: '6 Months',
                      badge: 'Save 27%',
                    ),
                    const SizedBox(width: 8),
                    _buildPlanCard(
                      plan: SubscriptionPlan.yearly,
                      priceText: '৳2499',
                      subtitle: '1 Year',
                      badge: 'Best Value',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                ...[
                  'Unlimited Scholarship Applications',
                  'Priority Scholarship Notifications',
                  'Advanced Application Tracking',
                  'Exclusive Premium Scholarships',
                  'Early Access to New Features',
                  'Priority Customer Support',
                ].map(
                  (x) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF5B7AE8)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            x,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (_isProcessing) ...[
                  Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF5B7AE8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage ?? 'Processing request...',
                          style: const TextStyle(
                            color: Color(0xFF5B7AE8),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                ElevatedButton(
                  onPressed: _isProcessing ? null : _handleUpgrade,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B7AE8),
                    disabledBackgroundColor:
                        const Color(0xFF5B7AE8).withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isProcessing
                        ? 'Processing...'
                        : 'Activate PRO (৳${_selectedPlan.amount})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (alreadyPremium)
                  TextButton(
                    onPressed: () async {
                      await provider.resetLocalDemo();
                      if (!mounted) return;
                      setState(() {
                        _paymentState = PaymentState.idle;
                        _statusMessage = null;
                        _errorMessage = null;
                      });
                    },
                    child: const Text(
                      'Reset to free tier (debug)',
                      style: TextStyle(color: Color(0xFF6B7A95)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required SubscriptionPlan plan,
    required String priceText,
    required String subtitle,
    String? badge,
  }) {
    final isSelected = _selectedPlan == plan;
    return Expanded(
      child: GestureDetector(
        onTap:
            _isProcessing ? null : () => setState(() => _selectedPlan = plan),
        child: AnimatedScale(
          scale: isSelected ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              vertical: isSelected ? 16 : 12,
              horizontal: isSelected ? 14 : 12,
            ),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5B7AE8) : Colors.white,
              borderRadius: BorderRadius.circular(isSelected ? 18 : 14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF3B5BDB)
                    : const Color(0xFFE2E8F0),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color:
                            const Color(0xFF5B7AE8).withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.amber
                          : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: isSelected ? 11 : 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.black
                            : const Color(0xFF5B7AE8),
                      ),
                    ),
                  ),
                Text(
                  plan.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isSelected ? 15 : 13,
                    color:
                        isSelected ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  priceText,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isSelected ? 17 : 14,
                    color:
                        isSelected ? Colors.white : const Color(0xFF5B7AE8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlreadyActiveCard(SubscriptionProvider provider) {
    final planLabel = provider.planId?.toUpperCase() ?? 'PRO';
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Color(0xFF059669)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are on the $planLabel plan — ${provider.daysRemaining} days remaining.',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF065F46),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    final provider = SubscriptionProviderScope.of(context);
    final planLabel =
        (provider.planId ?? _selectedPlan.id).toUpperCase();
    final daysRemaining = provider.daysRemaining;
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF059669)),
              SizedBox(width: 10),
              Text(
                'Premium Activated',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Color(0xFF065F46),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Plan: $planLabel • $daysRemaining days of PRO unlocked.',
            style: const TextStyle(color: Color(0xFF047857), fontSize: 13),
          ),
          if (provider.expiry != null) ...[
            const SizedBox(height: 6),
            Text(
              'Valid until: ${provider.expiry!.toLocal()}'.split('.').first,
              style: const TextStyle(fontSize: 12, color: Color(0xFF065F46)),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedCard() => Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                SizedBox(width: 10),
                Text(
                  'Activation Failed',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Color(0xFF991B1B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ??
                  'Something went wrong while activating premium.',
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _resetFlow,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
}