import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> getMetricsSummary() {
    return _getMap('/api/metrics/summary');
  }

  Future<Map<String, dynamic>> getMetricsRange(String period) {
    return _getMap('/api/metrics/range?period=$period');
  }

  Future<List<dynamic>> getReports() {
    return _getList('/api/reports');
  }

  Future<Map<String, dynamic>> getReport(int id) {
    return _getMap('/api/reports/$id');
  }

  Future<Map<String, dynamic>> clearReports() {
    return _deleteMap('/api/reports');
  }

  Future<List<dynamic>> getSchedules() {
    return _getList('/api/schedules');
  }

  Future<Map<String, dynamic>> createSchedule(
    String name,
    int intervalMinutes, {
    bool enabled = true,
  }) {
    return _postMap('/api/schedules', {
      'name': name,
      'interval_minutes': intervalMinutes,
      'enabled': enabled,
    });
  }

  Future<Map<String, dynamic>> toggleSchedule(int id) {
    return _postMap('/api/schedules/$id/toggle', {});
  }

  Future<Map<String, dynamic>> deleteSchedule(int id) {
    return _deleteMap('/api/schedules/$id');
  }

  Future<Map<String, dynamic>> runAgentNow() {
    return _postMap('/api/agent/run', {});
  }

  Future<Map<String, dynamic>> stopAgentNow() {
    return _postMap('/api/agent/stop', {});
  }

  Future<Map<String, dynamic>> getAgentStatus() {
    return _getMap('/api/agent/status');
  }

  Future<Map<String, dynamic>> resetPosts() {
    return _postMap('/api/posts/reset', {});
  }

  Future<Map<String, dynamic>> resetChat() {
    return _postMap('/api/chat/reset', {});
  }

  Future<Map<String, dynamic>> resetInvestment() {
    return _postMap('/api/investment/reset', {});
  }

  Future<String> getFaq() async {
    final data = await _getMap('/api/faq');
    return data['content']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> updateFaq(String content) {
    return _putMap('/api/faq', {'content': content});
  }

  Future<Map<String, dynamic>> _getMap(String path) async {
    final decoded = await _request('GET', path);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<List<dynamic>> _getList(String path) async {
    final decoded = await _request('GET', path);
    return decoded is List<dynamic> ? decoded : <dynamic>[];
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    final decoded = await _request('POST', path, body: body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _putMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    final decoded = await _request('PUT', path, body: body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _deleteMap(String path) async {
    final decoded = await _request('DELETE', path);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = {'Content-Type': 'application/json'};
      final encodedBody = body == null ? null : jsonEncode(body);
      late final http.Response response;

      switch (method) {
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        case 'PUT':
          response = await _client.put(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: headers);
          break;
        default:
          response = await _client.get(uri, headers: headers);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'error': true,
          'statusCode': response.statusCode,
          'message': response.body,
        };
      }

      if (response.body.trim().isEmpty) {
        return <String, dynamic>{};
      }

      return jsonDecode(response.body);
    } catch (error) {
      return {'error': true, 'message': error.toString()};
    }
  }

  void close() {
    _client.close();
  }
}
