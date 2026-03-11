import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'screens/pin_screen.dart';

void main() {
  runApp(const ClaudeRemoteApp());
}

class ClaudeRemoteApp extends StatelessWidget {
  const ClaudeRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFe94560),
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
      ),
      home: PinScreen(apiService: ApiService()),
    );
  }
}
