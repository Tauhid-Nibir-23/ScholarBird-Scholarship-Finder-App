import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum GatewayPaymentResult { success, failed, cancelled }

class PaymentGatewayScreen extends StatefulWidget {
  const PaymentGatewayScreen({required this.gatewayUrl, super.key});

  final String gatewayUrl;

  @override
  State<PaymentGatewayScreen> createState() => _PaymentGatewayScreenState();
}

class _PaymentGatewayScreenState extends State<PaymentGatewayScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final path = Uri.parse(request.url).path.toLowerCase();
            if (path.endsWith('/success')) {
              Navigator.pop(context, GatewayPaymentResult.success);
              return NavigationDecision.prevent;
            }
            if (path.endsWith('/fail')) {
              Navigator.pop(context, GatewayPaymentResult.failed);
              return NavigationDecision.prevent;
            }
            if (path.endsWith('/cancel')) {
              Navigator.pop(context, GatewayPaymentResult.cancelled);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.gatewayUrl));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Secure Payment')),
        body: WebViewWidget(controller: _controller),
      );
}
