import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UsageScreen extends StatefulWidget {
  final ApiService apiService;
  const UsageScreen({super.key, required this.apiService});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  Map<String, dynamic> _usage = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.apiService.getUsage();
    setState(() {
      _usage = data;
      _loading = false;
    });
  }

  String _formatNumber(dynamic n) {
    if (n == null) return '0';
    final num val = n is num ? n : 0;
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Token Usage'),
        backgroundColor: const Color(0xFF16213e),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFe94560)))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _tile(Icons.folder, 'Sessions', '${_usage['sessions'] ?? 0}'),
                  _tile(Icons.input, 'Input Tokens', _formatNumber(_usage['input_tokens'])),
                  _tile(Icons.output, 'Output Tokens', _formatNumber(_usage['output_tokens'])),
                  _tile(Icons.cached, 'Cache Read', _formatNumber(_usage['cache_read_tokens'])),
                  _tile(Icons.create, 'Cache Created', _formatNumber(_usage['cache_creation_tokens'])),
                  _tile(Icons.attach_money, 'Estimated Cost', '\$${_usage['cost_usd'] ?? 0}'),
                ],
              ),
            ),
    );
  }

  Widget _tile(IconData icon, String label, String value) {
    return Card(
      color: const Color(0xFF16213e),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFe94560)),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: Text(
          value,
          style: const TextStyle(
            color: Color(0xFFe94560),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
