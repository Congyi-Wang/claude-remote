import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/session_model.dart';
import 'terminal_screen.dart';
import 'usage_screen.dart';

class SessionListScreen extends StatefulWidget {
  final ApiService apiService;
  const SessionListScreen({super.key, required this.apiService});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<SessionModel> _chatSessions = [];
  List<Map<String, dynamic>> _terminalSessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.apiService.getSessions(),
        widget.apiService.getTerminalSessions(),
      ]);
      setState(() {
        _chatSessions = results[0] as List<SessionModel>;
        _terminalSessions = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // --- Open terminal ---

  void _openTerminal(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          sessionName: name,
          token: widget.apiService.token!,
        ),
      ),
    ).then((_) => _refresh());
  }

  // --- Resume a Claude chat session in a tmux terminal ---

  Future<void> _resumeChat(String sessionId, String title) async {
    // Use short name for tmux: "chat-<first 8 chars of session id>"
    final tmuxName = 'chat-${sessionId.substring(0, 8)}';

    // Check if this tmux session already exists
    final existing = _terminalSessions.any((s) => s['name'] == tmuxName);
    if (!existing) {
      try {
        await widget.apiService.createTerminalSession(
          tmuxName,
          command: 'claude --resume $sessionId --dangerously-skip-permissions',
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }
    _openTerminal(tmuxName);
  }

  // --- New Claude chat session in a tmux terminal ---

  Future<void> _newChat() async {
    // Create a tmux session running claude
    final tmuxName = 'claude-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    try {
      await widget.apiService.createTerminalSession(
        tmuxName,
        command: 'claude --dangerously-skip-permissions',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    _openTerminal(tmuxName);
  }

  // --- Create a plain terminal ---

  Future<void> _createTerminal() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('New Terminal', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Session name (e.g. dev-1)',
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

  Future<void> _deleteTerminal(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Kill Session?', style: TextStyle(color: Colors.white)),
        content: Text('Kill tmux session "$name"?',
            style: TextStyle(color: Colors.grey[300])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kill', style: TextStyle(color: Color(0xFFe94560))),
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

  // --- Helpers ---

  String _formatChatTime(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts);
      final diff = DateTime.now().toUtc().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  String _formatUnixTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final diff = DateTime.now().difference(dt);
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
        title: const Text('Claude Remote'),
        backgroundColor: const Color(0xFF16213e),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UsageScreen(apiService: widget.apiService),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFe94560)))
          : RefreshIndicator(
              color: const Color(0xFFe94560),
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // --- Terminal Sessions Section ---
                  _sectionHeader(
                    icon: Icons.terminal,
                    title: 'Terminals',
                    count: _terminalSessions.length,
                    onAdd: _createTerminal,
                  ),
                  if (_terminalSessions.isEmpty)
                    _emptyHint('No terminal sessions'),
                  ..._terminalSessions.map((s) {
                    final name = s['name'] as String;
                    final attached = (s['attached'] as int?) ?? 0;
                    final activity = (s['activity'] as int?) ?? 0;
                    return Card(
                      color: const Color(0xFF16213e),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.terminal,
                          color: attached > 0
                              ? const Color(0xFF4ade80)
                              : Colors.grey[600],
                          size: 28,
                        ),
                        title: Text(name, style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        )),
                        subtitle: Text(
                          '${attached > 0 ? "$attached attached" : "detached"} · ${_formatUnixTime(activity)}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.close, color: Colors.grey[600], size: 20),
                          onPressed: () => _deleteTerminal(name),
                        ),
                        onTap: () => _openTerminal(name),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  // --- Claude Chat Sessions Section ---
                  _sectionHeader(
                    icon: Icons.smart_toy_outlined,
                    title: 'Claude Sessions',
                    count: _chatSessions.length,
                    onAdd: _newChat,
                  ),
                  if (_chatSessions.isEmpty)
                    _emptyHint('No Claude sessions'),
                  ..._chatSessions.map((session) {
                    return Card(
                      color: const Color(0xFF16213e),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.smart_toy_outlined,
                          color: session.active ? Colors.greenAccent : Colors.grey[600],
                          size: 24,
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                        subtitle: Text(
                          '${session.messageCount} messages · ${_formatChatTime(session.updatedAt)}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        onTap: () => _resumeChat(session.id, session.title),
                      ),
                    );
                  }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFe94560), size: 20),
          const SizedBox(width: 8),
          Text(
            '$title ($count)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: const Icon(Icons.add_circle_outline, color: Color(0xFFe94560), size: 22),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
    );
  }
}
