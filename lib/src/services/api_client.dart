import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/entities.dart';

class ApiError implements Exception {
  const ApiError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.getAccessToken,
    required this.getRefreshToken,
    required this.onSessionRefreshed,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? Function() getAccessToken;
  final String? Function() getRefreshToken;
  final Future<void> Function(
    String accessToken,
    String refreshToken,
    AuthUser user,
  )
  onSessionRefreshed;
  final http.Client _http;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool retryOn401 = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (auth) {
      final token = getAccessToken();
      if (token == null || token.isEmpty) {
        throw const ApiError('Требуется авторизация');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _http.get(uri, headers: headers);
      case 'POST':
        response = await _http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      case 'PATCH':
        response = await _http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      case 'DELETE':
        response = await _http.delete(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      default:
        throw ApiError('Unsupported method: $method');
    }

    Map<String, dynamic> payload;
    try {
      payload = response.body.isNotEmpty
          ? (jsonDecode(response.body) as Map<String, dynamic>)
          : <String, dynamic>{};
    } catch (_) {
      payload = <String, dynamic>{};
    }

    if (response.statusCode == 401 && auth && retryOn401) {
      final refreshed = await refreshSession();
      if (refreshed != null) {
        return _request(
          method,
          path,
          body: body,
          auth: true,
          retryOn401: false,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        (payload['error'] ?? 'Ошибка запроса') as String,
        statusCode: response.statusCode,
      );
    }
    return payload;
  }

  Future<AuthSession?> refreshSession() async {
    final token = getRefreshToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    final payload = await _request(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': token},
      auth: false,
      retryOn401: false,
    );
    final session = AuthSession.fromJson(payload);
    await onSessionRefreshed(
      session.accessToken,
      session.refreshToken,
      session.user,
    );
    return session;
  }

  Future<Map<String, dynamic>> registerRequestCode(String email) {
    return _request(
      'POST',
      '/auth/register/request-code',
      body: {'email': email},
    );
  }

  Future<String> registerVerifyCode(String email, String code) async {
    final payload = await _request(
      'POST',
      '/auth/register/verify-code',
      body: {'email': email, 'code': code},
    );
    return (payload['registrationToken'] ?? '') as String;
  }

  Future<void> registerSetPassword({
    required String registrationToken,
    required String password,
    required String passwordConfirm,
  }) async {
    await _request(
      'POST',
      '/auth/register/set-password',
      body: {
        'registrationToken': registrationToken,
        'password': password,
        'passwordConfirm': passwordConfirm,
      },
    );
  }

  Future<AuthSession> registerCompleteProfile({
    required String registrationToken,
    required String displayName,
    required String username,
    required String bio,
    String? avatarUrl,
    String? identityPublicKey,
    String? signedPrekeyPublic,
    String? signedPrekeySignature,
    List<String>? oneTimePrekeys,
  }) async {
    final payload = await _request(
      'POST',
      '/auth/register/complete-profile',
      body: {
        'registrationToken': registrationToken,
        'displayName': displayName,
        'username': username,
        'bio': bio,
        'avatarUrl': avatarUrl ?? '',
        if (identityPublicKey != null) 'identityPublicKey': identityPublicKey,
        if (signedPrekeyPublic != null)
          'signedPrekeyPublic': signedPrekeyPublic,
        if (signedPrekeySignature != null)
          'signedPrekeySignature': signedPrekeySignature,
        if (oneTimePrekeys != null) 'oneTimePrekeys': oneTimePrekeys,
      },
    );
    return AuthSession.fromJson(payload);
  }

  Future<Map<String, dynamic>> loginRequest({
    required String email,
    required String password,
  }) {
    return _request(
      'POST',
      '/auth/login/request',
      body: {'email': email, 'password': password},
    );
  }

  Future<AuthSession> loginVerify({
    required String challengeId,
    required String code,
  }) async {
    final payload = await _request(
      'POST',
      '/auth/login/verify',
      body: {'challengeId': challengeId, 'code': code},
    );
    return AuthSession.fromJson(payload);
  }

  Future<void> logout() {
    return _request('POST', '/auth/logout', auth: true);
  }

  Future<AuthUser> getMe() async {
    final payload = await _request('GET', '/auth/me', auth: true);
    return AuthUser.fromJson(
      (payload['user'] ?? const {}) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> getMyProfile() {
    return _request('GET', '/users/me', auth: true);
  }

  Future<AuthUser> updateMyProfile({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bio,
    String? birthDate,
  }) async {
    final payload = await _request(
      'PATCH',
      '/users/me',
      auth: true,
      body: {
        if (displayName != null) 'displayName': displayName,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (birthDate != null) 'birthDate': birthDate,
      },
    );
    return AuthUser.fromJson(
      (payload['user'] ?? const {}) as Map<String, dynamic>,
    );
  }

  Future<void> updatePrivacy({
    String? avatarVisibility,
    String? bioVisibility,
    String? lastSeenVisibility,
  }) {
    return _request(
      'PATCH',
      '/users/me/privacy',
      auth: true,
      body: {
        if (avatarVisibility != null) 'avatarVisibility': avatarVisibility,
        if (bioVisibility != null) 'bioVisibility': bioVisibility,
        if (lastSeenVisibility != null)
          'lastSeenVisibility': lastSeenVisibility,
      },
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _request(
      'POST',
      '/users/me/change-password',
      auth: true,
      body: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
  }

  Future<List<Map<String, dynamic>>> getMySessions() async {
    final payload = await _request('GET', '/users/me/sessions', auth: true);
    return ((payload['sessions'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> revokeMySession(String sessionId) {
    return _request('DELETE', '/users/me/sessions/$sessionId', auth: true);
  }

  Future<List<Contact>> getContacts({String query = ''}) async {
    final payload = await _request(
      'GET',
      '/contacts${query.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(query)}'}',
      auth: true,
    );
    return ((payload['contacts'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => Contact.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<String> openDirectChat(String username) async {
    final payload = await _request(
      'POST',
      '/chats/direct',
      body: {'username': username},
      auth: true,
    );
    return (payload['chatId'] ?? '') as String;
  }

  Future<List<ChatItem>> getChats(CtrlTab tab) async {
    final payload = await _request(
      'GET',
      '/chats?tab=${tab.apiTab}',
      auth: true,
    );
    return ((payload['chats'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => ChatItem.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<List<CallLog>> getCalls() async {
    final payload = await _request('GET', '/calls', auth: true);
    return ((payload['calls'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => CallLog.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateChatPreferences(
    String chatId, {
    bool? muted,
    bool? pinned,
    bool? favorite,
    bool? archived,
  }) async {
    await _request(
      'PATCH',
      '/chats/$chatId/preferences',
      auth: true,
      body: {
        if (muted != null) 'muted': muted,
        if (pinned != null) 'pinned': pinned,
        if (favorite != null) 'favorite': favorite,
        if (archived != null) 'archived': archived,
      },
    );
  }

  Future<List<ChatMessage>> getMessages(String chatId) async {
    final payload = await _request(
      'GET',
      '/chats/$chatId/messages',
      auth: true,
    );
    return ((payload['messages'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => ChatMessage.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String chatId,
    required String text,
    String? ciphertext,
    String? type,
    String? replyToId,
  }) async {
    final payload = await _request(
      'POST',
      '/chats/$chatId/messages',
      auth: true,
      body: {
        'text': text,
        if (ciphertext != null) 'ciphertext': ciphertext,
        if (type != null) 'type': type,
        if (replyToId != null) 'replyToId': replyToId,
      },
    );
    return ChatMessage.fromJson(
      (payload['message'] ?? const {}) as Map<String, dynamic>,
    );
  }

  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    await _request(
      'PATCH',
      '/messages/$messageId',
      auth: true,
      body: {'text': text},
    );
  }

  Future<void> deleteMessage({
    required String messageId,
    required String scope,
  }) async {
    await _request('DELETE', '/messages/$messageId?scope=$scope', auth: true);
  }

  Future<void> reactMessage({
    required String messageId,
    required String emoji,
  }) async {
    await _request(
      'POST',
      '/messages/$messageId/reactions',
      auth: true,
      body: {'emoji': emoji},
    );
  }

  Future<List<Map<String, dynamic>>> search({
    required String query,
    required String scope,
  }) async {
    final payload = await _request(
      'GET',
      '/search?q=${Uri.encodeQueryComponent(query)}&scope=$scope',
      auth: true,
    );
    return ((payload['results'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> report({
    required String reason,
    String? details,
    int? targetUserId,
    String? messageId,
  }) async {
    await _request(
      'POST',
      '/reports',
      auth: true,
      body: {
        'reason': reason,
        if (details != null) 'details': details,
        if (targetUserId != null) 'targetUserId': targetUserId,
        if (messageId != null) 'messageId': messageId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getStickerPacks() async {
    final payload = await _request('GET', '/stickers/packs', auth: true);
    return ((payload['packs'] ?? const <dynamic>[]) as List<dynamic>)
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> createStickerPack(String title) async {
    await _request(
      'POST',
      '/stickers/packs',
      auth: true,
      body: {'title': title},
    );
  }

  Future<void> uploadCryptoKeys({
    required String identityPublicKey,
    required String signedPrekeyPublic,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  }) async {
    await _request(
      'POST',
      '/crypto/keys',
      auth: true,
      body: {
        'identityPublicKey': identityPublicKey,
        'signedPrekeyPublic': signedPrekeyPublic,
        'signedPrekeySignature': signedPrekeySignature,
        'oneTimePrekeys': oneTimePrekeys,
      },
    );
  }

  Future<Map<String, dynamic>> getPublicProfile(String username) {
    return _request('GET', '/users/profile/$username');
  }
}
