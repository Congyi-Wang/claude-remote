import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/session_model.dart';
import 'chat_screen.dart';
import 'usage_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  const HomeScreen({super.key, required this.apiService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SessionModel> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    final sessions = await widget.apiService.getSessions();
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  void _openChat(String sessionId, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          apiService: widget.apiService,
          sessionId: sessionId,
          title: title,
        ),
      ),
    ).then((_) => _loadSessions());
  }

  void _newSession() {
    _openChat('new', 'New Session');
  }

  Future<void> _deleteSession(String sessionId) async {
    await widget.apiService.deleteSession(sessionId);
    _loadSessions();
  }

  String _formatTime(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts);
      final now = DateTime.now().toUtc();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
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
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFe94560)))
          : _sessions.isEmpty
              ? Center(
                  child: Text(
                    'No sessions yet.\nTap + to start one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _sessions.length,
                    itemBuilder: (ctx, i) => _buildCard(_sessions[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFe94560),
        onPressed: _newSession,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildCard(SessionModel session) {
    return Card(
      color: const Color(0xFF16213e),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          session.active ? Icons.circle : Icons.circle_outlined,
          color: session.active ? Colors.greenAccent : Colors.grey[600],
          size: 14,
        ),
        title: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        subtitle: Text(
          '${session.messageCount} messages · ${_formatTime(session.updatedAt)}',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close, color: Colors.grey[600], size: 20),
          onPressed: () => _deleteSession(session.id),
        ),
        onTap: () => _openChat(session.id, session.title),
      ),
    );
  }
}
