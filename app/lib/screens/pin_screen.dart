import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class PinScreen extends StatefulWidget {
  final ApiService apiService;
  const PinScreen({super.key, required this.apiService});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  bool _loading = false;
  String? _error;

  void _addDigit(String digit) {
    if (_pin.length < 6) {
      setState(() {
        _pin += digit;
        _error = null;
      });
      if (_pin.length == 6) {
        _submit();
      }
    }
  }

  void _deleteDigit() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final ok = await widget.apiService.login(_pin);
    setState(() => _loading = false);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(apiService: widget.apiService),
        ),
      );
    } else {
      setState(() {
        _pin = '';
        _error = 'Invalid PIN';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cell_tower, size: 64, color: Color(0xFFe94560)),
            const SizedBox(height: 16),
            const Text(
              'Claude Remote',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter PIN to continue',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? const Color(0xFFe94560)
                        : Colors.grey[700],
                  ),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_loading) ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(color: Color(0xFFe94560)),
            ],
            const SizedBox(height: 40),
            // Numpad
            _buildNumpad(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        _numRow(['1', '2', '3']),
        _numRow(['4', '5', '6']),
        _numRow(['7', '8', '9']),
        _numRow(['', '0', '⌫']),
      ],
    );
  }

  Widget _numRow(List<String> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys.map((k) {
          if (k.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(width: 72),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () {
                if (k == '⌫') {
                  _deleteDigit();
                } else {
                  _addDigit(k);
                }
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
                alignment: Alignment.center,
                child: Text(
                  k,
                  style: const TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
