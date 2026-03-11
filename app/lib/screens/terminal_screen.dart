import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TerminalScreen extends StatefulWidget {
  final String sessionName;
  final String token;
  const TerminalScreen({super.key, required this.sessionName, required this.token});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  String get _terminalUrl =>
      'http://46.224.150.45/claude-remote/api/terminals/${Uri.encodeComponent(widget.sessionName)}/page'
      '?session=${Uri.encodeComponent(widget.sessionName)}'
      '&token=${Uri.encodeComponent(widget.token)}';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() {
          _loading = false;
          _error = null;
        }),
        onWebResourceError: (error) {
          setState(() {
            _loading = false;
            _error = error.description;
          });
        },
      ))
      ..setBackgroundColor(const Color(0xFF1a1a2e))
      ..loadRequest(Uri.parse(_terminalUrl));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFe94560)),
            ),
          if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Connection failed',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFe94560),
                    ),
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _loading = true;
                      });
                      _controller.loadRequest(Uri.parse(_terminalUrl));
                    },
                    child: const Text('Retry',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
