import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'terminal_screen.dart';

class SessionListScreen extends StatefulWidget {
  final ApiService apiService;
  const SessionListScreen({super.key, required this.apiService});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final sessions = await widget.apiService.getTerminalSessions();
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _openSession(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          sessionName: name,
          token: widget.apiService.token!,
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('New Session', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Session name (e.g. claude-1)',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFe94560)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFe94560), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create', style: TextStyle(color: Color(0xFFe94560))),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        await widget.apiService.createTerminalSession(name);
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteSession(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Delete Session?', style: TextStyle(color: Colors.white)),
        content: Text('Kill tmux session "$name"?',
            style: TextStyle(color: Colors.grey[300])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFe94560))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.apiService.deleteTerminalSession(name);
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Terminal Sessions'),
        backgroundColor: const Color(0xFF16213e),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFe94560)))
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.terminal, size: 64, color: Colors.grey[700]),
                      const SizedBox(height: 16),
                      Text('No sessions', style: TextStyle(color: Colors.grey[500], fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Tap + to create one', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFFe94560),
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _sessions.length,
                    itemBuilder: (ctx, i) {
                      final s = _sessions[i];
                      final name = s['name'] as String;
                      final attached = (s['attached'] as int?) ?? 0;
                      final activity = (s['activity'] as int?) ?? 0;
                      return Card(
                        color: const Color(0xFF16213e),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            Icons.terminal,
                            color: attached > 0 ? const Color(0xFF4ade80) : Colors.grey[600],
                            size: 32,
                          ),
                          title: Text(name, style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16,
                          )),
                          subtitle: Text(
                            '${attached > 0 ? "$attached attached" : "detached"} · ${_formatTime(activity)}',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                            onPressed: () => _deleteSession(name),
                          ),
                          onTap: () => _openSession(name),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFe94560),
        onPressed: _createSession,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
