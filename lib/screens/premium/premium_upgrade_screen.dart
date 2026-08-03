import 'package:flutter/material.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription_service.dart';
import 'payment_gateway_screen.dart';

enum PaymentState {
  idle,
  creatingPayment,
  openingGateway,
  waitingForCompletion,
  verifying,
  success,
  cancelled,
  failed,
}

class PremiumUpgradeScreen extends StatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _phoneController = TextEditingController();

  SubscriptionPlan _selectedPlan = SubscriptionPlan.monthly;
  PaymentState _paymentState = PaymentState.idle;

  String? _transactionId;
  String? _statusMessage;
  String? _errorMessage;
  PaymentValidationResult? _validationResult;

  bool get _isProcessing =>
      _paymentState == PaymentState.creatingPayment ||
      _paymentState == PaymentState.openingGateway ||
      _paymentState == PaymentState.verifying;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleUpgrade() async {
    if (_isProcessing) return; // Prevent duplicate requests

    setState(() {
      _paymentState = PaymentState.creatingPayment;
      _statusMessage = 'Creating secure payment session...';
      _errorMessage = null;
      _validationResult = null;
    });

    try {
      final session = await _subscriptionService.createPaymentSession(
        plan: _selectedPlan,
        phone: _phoneController.text.trim(),
      );

      _transactionId = session.transactionId;

      setState(() {
        _paymentState = PaymentState.openingGateway;
        _statusMessage = 'Opening SSLCommerz Payment Gateway...';
      });

      setState(() {
        _paymentState = PaymentState.waitingForCompletion;
        _statusMessage = 'Complete your payment in the secure gateway.';
      });

      final gatewayResult = await Navigator.push<GatewayPaymentResult>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentGatewayScreen(gatewayUrl: session.gatewayUrl),
        ),
      );

      if (!mounted) return;
      if (gatewayResult == GatewayPaymentResult.success) {
        await _verifyPayment();
      } else {
        setState(() {
          _paymentState = PaymentState.failed;
          _errorMessage = 'Payment Failed';
        });
      }
    } on PaymentException catch (e) {
      setState(() {
        _paymentState = PaymentState.failed;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _paymentState = PaymentState.failed;
        _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      });
    }
  }

  Future<void> _verifyPayment() async {
    if (_transactionId == null || _transactionId!.isEmpty || _isProcessing) {
      return;
    }

    setState(() {
      _paymentState = PaymentState.verifying;
      _statusMessage = 'Verifying payment status with backend server...';
      _errorMessage = null;
    });

    try {
      final result =
          await _subscriptionService.validatePayment(_transactionId!);

      _validationResult = result;

      if (result.isValid) {
        setState(() {
          _paymentState = PaymentState.success;
          _statusMessage = 'Payment Successful!';
        });
      } else if (result.isCancelled) {
        setState(() {
          _paymentState = PaymentState.cancelled;
          _statusMessage = 'Payment Cancelled.';
        });
      } else {
        setState(() {
          _paymentState = PaymentState.failed;
          _errorMessage =
              'Backend payment validation failed. Status: ${result.status}';
        });
      }
    } on PaymentException catch (e) {
      setState(() {
        _paymentState = PaymentState.failed;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _paymentState = PaymentState.failed;
        _errorMessage = 'Backend verification failed: ${e.toString()}';
      });
    }
  }

  void _resetFlow() {
    setState(() {
      _paymentState = PaymentState.idle;
      _transactionId = null;
      _statusMessage = null;
      _errorMessage = null;
      _validationResult = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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

                // Status / Feedback Cards
                if (_paymentState == PaymentState.success) _buildSuccessCard(),
                if (_paymentState == PaymentState.cancelled)
                  _buildCancelledCard(),
                if (_paymentState == PaymentState.failed) _buildFailedCard(),
                if (_paymentState == PaymentState.waitingForCompletion)
                  _buildWaitingForCompletionCard(),

                if (_paymentState == PaymentState.idle || _isProcessing) ...[
                  // Plan Selector
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
                  const SizedBox(height: 20),

                  // Contact Phone Input (Optional)
                  TextField(
                    controller: _phoneController,
                    enabled: !_isProcessing,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Mobile Number (Optional)',
                      hintText: 'e.g. 01711223344',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Features list
                  ...[
                    'Unlimited Scholarship Applications',
                    'Priority Scholarship Notifications',
                    'Advanced Application Tracking',
                    'Exclusive Premium Scholarships',
                    'Early Access to New Features',
                    'Priority Customer Support',
                  ].map((x) => Padding(
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
                      )),
                  const SizedBox(height: 24),

                  // Loading Indicator / Status text during operation
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

                  // Action Button
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
                          : 'Upgrade to PRO (৳${_selectedPlan.amount})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

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
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF5B7AE8) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF5B7AE8)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF5B7AE8).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected ? Colors.black : const Color(0xFF5B7AE8),
                    ),
                  ),
                ),
              Text(
                plan.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                priceText,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: isSelected ? Colors.white : const Color(0xFF5B7AE8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingForCompletionCard() => Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.open_in_new, color: Color(0xFF2563EB)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SSLCommerz Gateway Opened',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _statusMessage ??
                  'Please complete payment in the opened browser window.',
              style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 13),
            ),
            if (_transactionId != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Transaction ID: $_transactionId',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _verifyPayment,
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Verify Payment Status'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _resetFlow,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildSuccessCard() => Container(
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
                  'Payment Successful',
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
              'Backend validation confirmed payment for plan ${_selectedPlan.label}.',
              style: const TextStyle(color: Color(0xFF047857), fontSize: 13),
            ),
            if (_validationResult != null) ...[
              const SizedBox(height: 6),
              Text(
                'Transaction ID: ${_validationResult!.transactionId}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF065F46),
                ),
              ),
              if (_validationResult!.amount != null)
                Text(
                  'Amount Paid: ৳${_validationResult!.amount} ${_validationResult!.currency ?? 'BDT'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF065F46),
                  ),
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

  Widget _buildCancelledCard() => Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 10),
                Text(
                  'Payment Cancelled',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'The payment transaction was cancelled. No charges were processed.',
              style: TextStyle(color: Color(0xFFB45309), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _resetFlow,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );

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
                  'Payment Failed',
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
                  'Backend validation failed or payment could not be processed.',
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
