import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/session_model.dart';
import '../models/message_model.dart';

class ApiService {
  static const String baseUrl = 'http://46.224.150.45/claude-remote';
  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null;

  Future<bool> login(String pin) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _token = data['token'];
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<SessionModel>> getSessions() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/sessions/?token=$_token'),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = data['sessions'] as List;
      return list.map((j) => SessionModel.fromJson(j)).toList();
    }
    return [];
  }

  Future<List<MessageModel>> getMessages(String sessionId) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/sessions/$sessionId/messages?token=$_token'),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final list = data['messages'] as List;
      return list.map((j) => MessageModel.fromJson(j)).toList();
    }
    return [];
  }

  Future<void> deleteSession(String sessionId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/sessions/$sessionId?token=$_token'),
    );
  }

  Future<Map<String, dynamic>> getUsage() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/usage/?token=$_token'),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    }
    return {};
  }
}
