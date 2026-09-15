import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/dictionary.dart';
import '../models/word.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Thin wrapper around the GuYo backend REST API. Holds the JWT in secure
/// storage (Android Keystore-backed) rather than plain SharedPreferences.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'guyo_user_token';

  String? _cachedToken;

  Future<String?> get token async {
    _cachedToken ??= await _storage.read(key: _tokenKey);
    return _cachedToken;
  }

  Future<void> _saveToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> get isLoggedIn async => (await token) != null;

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<Map<String, String>> _authHeaders() async {
    final t = await token;
    return {
      'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  /// Returns full media URL for a relative path like "/media/....png".
  String mediaUrl(String relativePath) => '$apiBaseUrl$relativePath';

  Future<void> login(String login, String password) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password}),
    );
    if (res.statusCode == 401) {
      throw ApiException('Неверный логин или пароль', statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException('Ошибка сервера (${res.statusCode})', statusCode: res.statusCode);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    await _saveToken(data['access_token'] as String);
  }

  Future<void> logout() async {
    await clearToken();
  }

  Future<List<GuyoDictionary>> fetchDictionaries() async {
    final res = await http.get(_uri('/dictionaries'), headers: await _authHeaders());
    _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoDictionary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<GuyoWord>> fetchWords(int dictionaryId) async {
    final res = await http.get(
      _uri('/dictionaries/$dictionaryId/words'),
      headers: await _authHeaders(),
    );
    _throwIfUnauthorized(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _throwIfUnauthorized(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw ApiException('Сессия истекла, войдите снова', statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw ApiException('Ошибка сервера (${res.statusCode})', statusCode: res.statusCode);
    }
  }
}
