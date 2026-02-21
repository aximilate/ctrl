import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/entities.dart';
import '../services/api_client.dart';
import '../services/crypto_service.dart';
import '../services/session_store.dart';

const _defaultApiUrl = String.fromEnvironment(
  'CTRLCHAT_API_URL',
  defaultValue: 'http://localhost:8080/api',
);

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

class CtrlChatState extends ChangeNotifier {
  CtrlChatState()
    : _store = SessionStore(),
      _crypto = CryptoService(),
      _baseUrl = _normalizeBaseUrl(_defaultApiUrl),
      _api = ApiClient(
        baseUrl: _normalizeBaseUrl(_defaultApiUrl),
        getAccessToken: () => _instance?._activeSession?.accessToken,
        getRefreshToken: () => _instance?._activeSession?.refreshToken,
        onSessionRefreshed: (accessToken, refreshToken, user) async {
          final state = _instance;
          if (state == null) {
            return;
          }
          final session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: user,
          );
          await state._applySession(session, setActive: true, notify: true);
        },
      ) {
    _instance = this;
  }

  final SessionStore _store;
  final CryptoService _crypto;
  final String _baseUrl;
  final ApiClient _api;
  static CtrlChatState? _instance;

  bool _initialized = false;
  bool _loading = false;
  String? _error;

  AuthSession? _activeSession;
  List<StoredAccount> _accounts = const <StoredAccount>[];

  CtrlTab _currentTab = CtrlTab.home;
  List<ChatItem> _chats = const <ChatItem>[];
  List<Contact> _contacts = const <Contact>[];
  List<CallLog> _calls = const <CallLog>[];
  String? _selectedChatId;
  final Map<String, List<ChatMessage>> _messagesByChat =
      <String, List<ChatMessage>>{};
  final Map<String, List<Map<String, dynamic>>> _searchByScope =
      <String, List<Map<String, dynamic>>>{};
  Map<String, String> _privacy = const <String, String>{
    'avatarVisibility': 'everyone',
    'bioVisibility': 'everyone',
    'lastSeenVisibility': 'contacts',
  };
  List<Map<String, dynamic>> _sessions = const <Map<String, dynamic>>[];
  String _searchScope = 'messages';
  String _searchQuery = '';

  String? _loginChallengeId;
  String? _registerFlowToken;
  String? _devCodeHint;
  String? _pendingEmail;
  String? _identityPrivateKey;
  String? _peerIdentityKeyForCurrentChat;
  int _localMessageCounter = 1;
  String? _replyToMessageId;
  bool _voiceHoldMode = false;
  bool _videoNoteMode = false;

  bool get initialized => _initialized;
  bool get loading => _loading;
  String? get error => _error;
  String get apiBaseUrl => _baseUrl;

  bool get isAuthenticated => _activeSession != null;
  AuthSession? get activeSession => _activeSession;
  AuthUser? get currentUser => _activeSession?.user;
  List<StoredAccount> get accounts => _accounts;

  CtrlTab get currentTab => _currentTab;
  List<ChatItem> get chats => _chats;
  List<Contact> get contacts => _contacts;
  List<CallLog> get calls => _calls;
  String? get selectedChatId => _selectedChatId;
  List<ChatMessage> get selectedMessages {
    if (_selectedChatId == null) {
      return const <ChatMessage>[];
    }
    return _messagesByChat[_selectedChatId!] ?? const <ChatMessage>[];
  }

  ChatItem? get selectedChat {
    if (_selectedChatId == null) {
      return null;
    }
    for (final chat in _chats) {
      if (chat.id == _selectedChatId) {
        return chat;
      }
    }
    return null;
  }

  String get searchScope => _searchScope;
  String get searchQuery => _searchQuery;
  List<Map<String, dynamic>> get searchResults =>
      _searchByScope[_searchScope] ?? const [];
  Map<String, String> get privacy => _privacy;
  List<Map<String, dynamic>> get sessions => _sessions;
  String? get loginChallengeId => _loginChallengeId;
  String? get registerFlowToken => _registerFlowToken;
  String? get devCodeHint => _devCodeHint;
  String? get pendingEmail => _pendingEmail;
  String? get replyToMessageId => _replyToMessageId;
  bool get voiceHoldMode => _voiceHoldMode;
  bool get videoNoteMode => _videoNoteMode;

  Future<void> init() async {
    _setLoading(true);
    _error = null;
    try {
      _accounts = _deduplicateAccounts(await _store.loadAccounts());
      final activeId = await _store.loadActiveUserId();
      if (_accounts.isNotEmpty) {
        final selected = _accounts.firstWhere(
          (entry) => entry.session.user.id == activeId,
          orElse: () => _accounts.first,
        );
        _activeSession = selected.session;
        await _api.refreshSession();
        await _loadTabData(_currentTab, keepSelection: false);
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _initialized = true;
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loginRequest({
    required String email,
    required String password,
  }) async {
    _error = null;
    _setLoading(true);
    try {
      final payload = await _api.loginRequest(email: email, password: password);
      _loginChallengeId = payload['challengeId'] as String?;
      _devCodeHint = payload['devCode'] as String?;
      _pendingEmail = email;
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loginVerify({required String code}) async {
    final challenge = _loginChallengeId;
    if (challenge == null) {
      throw const ApiError('Нет активного challenge для входа');
    }
    _error = null;
    _setLoading(true);
    try {
      final session = await _api.loginVerify(
        challengeId: challenge,
        code: code,
      );
      await _applySession(session, setActive: true, notify: false);
      _loginChallengeId = null;
      _devCodeHint = null;
      _pendingEmail = null;
      await _loadTabData(CtrlTab.home, keepSelection: false);
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> registerRequestCode({required String email}) async {
    _error = null;
    _setLoading(true);
    try {
      final payload = await _api.registerRequestCode(email);
      _devCodeHint = payload['devCode'] as String?;
      _pendingEmail = email;
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> registerVerifyCode({
    required String email,
    required String code,
  }) async {
    _error = null;
    _setLoading(true);
    try {
      _registerFlowToken = await _api.registerVerifyCode(email, code);
      _pendingEmail = email;
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> registerSetPassword({
    required String password,
    required String passwordConfirm,
  }) async {
    final flow = _registerFlowToken;
    if (flow == null) {
      throw const ApiError('Нет активного токена регистрации');
    }
    _error = null;
    _setLoading(true);
    try {
      await _api.registerSetPassword(
        registrationToken: flow,
        password: password,
        passwordConfirm: passwordConfirm,
      );
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> registerCompleteProfile({
    required String displayName,
    required String username,
    required String bio,
    String? avatarUrl,
  }) async {
    final flow = _registerFlowToken;
    if (flow == null) {
      throw const ApiError('Нет активного токена регистрации');
    }
    _error = null;
    _setLoading(true);
    try {
      final cryptoPayload = await _crypto.createRegistrationPayload();
      _identityPrivateKey = cryptoPayload.identityPrivateKey;
      final session = await _api.registerCompleteProfile(
        registrationToken: flow,
        displayName: displayName,
        username: username,
        bio: bio,
        avatarUrl: avatarUrl,
        identityPublicKey: cryptoPayload.identityPublicKey,
        signedPrekeyPublic: cryptoPayload.signedPrekeyPublic,
        signedPrekeySignature: cryptoPayload.signedPrekeySignature,
        oneTimePrekeys: cryptoPayload.oneTimePrekeys,
      );
      await _applySession(session, setActive: true, notify: false);
      _registerFlowToken = null;
      _pendingEmail = null;
      _devCodeHint = null;
      await _loadTabData(CtrlTab.home, keepSelection: false);
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> logoutActive() async {
    _error = null;
    _setLoading(true);
    try {
      if (_activeSession != null) {
        await _api.logout();
      }
    } catch (_) {
      // ignore logout failure
    } finally {
      if (_activeSession != null) {
        _accounts = _accounts
            .where((entry) => entry.session.user.id != _activeSession!.user.id)
            .toList(growable: false);
      }
      _activeSession = _accounts.isNotEmpty ? _accounts.first.session : null;
      await _store.saveAccounts(_accounts, _activeSession?.user.id);
      _clearRuntimeData();
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> switchAccount(int userId) async {
    final candidate = _accounts
        .where((entry) => entry.session.user.id == userId)
        .toList();
    if (candidate.isEmpty) {
      return;
    }
    _activeSession = candidate.first.session;
    await _store.saveAccounts(_accounts, userId);
    _clearRuntimeData(keepAuth: true);
    notifyListeners();
    await _loadTabData(CtrlTab.home, keepSelection: false);
  }

  Future<bool> canAddAccount() async {
    return _accounts.length < 3;
  }

  Future<void> loadTab(CtrlTab tab) async {
    _currentTab = tab;
    notifyListeners();
    await _loadTabData(tab, keepSelection: true);
  }

  Future<void> _loadTabData(CtrlTab tab, {required bool keepSelection}) async {
    if (_activeSession == null) {
      return;
    }
    _error = null;
    _setLoading(true);
    try {
      switch (tab) {
        case CtrlTab.home:
        case CtrlTab.favorites:
          _chats = await _api.getChats(tab);
          if (_chats.isEmpty) {
            _selectedChatId = null;
          } else {
            final hasCurrent =
                keepSelection &&
                _selectedChatId != null &&
                _chats.any((entry) => entry.id == _selectedChatId);
            _selectedChatId = hasCurrent ? _selectedChatId : _chats.first.id;
            if (_selectedChatId != null) {
              await _loadMessages(_selectedChatId!);
            }
          }
        case CtrlTab.contacts:
          _contacts = await _api.getContacts();
        case CtrlTab.calls:
          _calls = await _api.getCalls();
        case CtrlTab.settings:
          await _loadSettingsSnapshot();
      }
    } on ApiError catch (error) {
      _error = error.message;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> openChat(String chatId) async {
    _selectedChatId = chatId;
    notifyListeners();
    await _loadMessages(chatId);
  }

  Future<void> openDirectChatByUsername(String username) async {
    _error = null;
    _setLoading(true);
    try {
      final chatId = await _api.openDirectChat(username);
      await _loadTabData(CtrlTab.home, keepSelection: true);
      _selectedChatId = chatId;
      await _loadMessages(chatId);
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> _loadMessages(String chatId) async {
    final messages = await _api.getMessages(chatId);
    _messagesByChat[chatId] = messages;
    notifyListeners();
  }

  Future<void> sendMessage(String text, {String? type}) async {
    final chatId = _selectedChatId;
    if (chatId == null || text.trim().isEmpty) {
      return;
    }
    _error = null;
    final content = text.trim();
    try {
      String? ciphertext;
      if (_identityPrivateKey != null &&
          _peerIdentityKeyForCurrentChat != null) {
        final secret = await _crypto.deriveSharedSecret(
          privateKeyBase64: _identityPrivateKey!,
          publicKeyBase64: _peerIdentityKeyForCurrentChat!,
        );
        final encrypted = await _crypto.encryptMessage(
          sharedSecret: secret,
          plaintext: content,
          counter: _localMessageCounter,
        );
        _localMessageCounter += 1;
        ciphertext = encrypted.toJsonString();
      }

      final message = await _api.sendMessage(
        chatId: chatId,
        text: content,
        ciphertext: ciphertext,
        replyToId: _replyToMessageId,
        type: type ?? (_videoNoteMode ? 'video_note' : 'text'),
      );
      final list = List<ChatMessage>.from(
        _messagesByChat[chatId] ?? const <ChatMessage>[],
      );
      list.add(message);
      _messagesByChat[chatId] = list;
      _replyToMessageId = null;
      _videoNoteMode = false;
      await _loadTabData(_currentTab, keepSelection: true);
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendAttachment({
    required String attachmentKind,
    required String fileName,
  }) {
    final type = attachmentKind == 'media' ? 'media' : 'file';
    final label = switch (attachmentKind) {
      'media' => '[MEDIA] $fileName',
      'document' => '[DOC] $fileName',
      _ => '[FILE] $fileName',
    };
    return sendMessage(label, type: type);
  }

  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }
    await _api.editMessage(messageId: messageId, text: text);
    await _loadMessages(chatId);
  }

  Future<void> deleteMessage({
    required String messageId,
    required String scope,
  }) async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }
    await _api.deleteMessage(messageId: messageId, scope: scope);
    await _loadMessages(chatId);
  }

  Future<void> reactToMessage({
    required String messageId,
    required String emoji,
  }) async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }
    await _api.reactMessage(messageId: messageId, emoji: emoji);
    await _loadMessages(chatId);
  }

  Future<void> updateChatPreferences(
    String chatId, {
    bool? muted,
    bool? pinned,
    bool? favorite,
    bool? archived,
  }) async {
    await _api.updateChatPreferences(
      chatId,
      muted: muted,
      pinned: pinned,
      favorite: favorite,
      archived: archived,
    );
    await _loadTabData(_currentTab, keepSelection: true);
  }

  void setReplyTo(String? messageId) {
    _replyToMessageId = messageId;
    notifyListeners();
  }

  void setVoiceHoldMode(bool value) {
    _voiceHoldMode = value;
    notifyListeners();
  }

  void toggleVideoNoteMode() {
    _videoNoteMode = !_videoNoteMode;
    notifyListeners();
  }

  Future<void> search({required String query, required String scope}) async {
    _searchQuery = query;
    _searchScope = scope;
    if (query.trim().isEmpty) {
      _searchByScope[scope] = const [];
      notifyListeners();
      return;
    }
    try {
      final results = await _api.search(query: query, scope: scope);
      _searchByScope[scope] = results;
      notifyListeners();
    } on ApiError catch (error) {
      _error = error.message;
      notifyListeners();
    }
  }

  Future<void> report({
    required String reason,
    String? details,
    int? targetUserId,
    String? messageId,
  }) async {
    await _api.report(
      reason: reason,
      details: details,
      targetUserId: targetUserId,
      messageId: messageId,
    );
  }

  Future<List<Map<String, dynamic>>> getStickerPacks() =>
      _api.getStickerPacks();

  Future<void> createStickerPack(String title) => _api.createStickerPack(title);

  Future<Map<String, dynamic>> getPublicProfile(String username) =>
      _api.getPublicProfile(username);

  Future<void> refreshSettings() async {
    _error = null;
    _setLoading(true);
    try {
      await _loadSettingsSnapshot();
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bio,
    String? birthDate,
  }) async {
    _error = null;
    _setLoading(true);
    try {
      final user = await _api.updateMyProfile(
        displayName: displayName,
        username: username,
        avatarUrl: avatarUrl,
        bio: bio,
        birthDate: birthDate,
      );
      await _replaceCurrentUser(user);
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> updatePrivacy({
    String? avatarVisibility,
    String? bioVisibility,
    String? lastSeenVisibility,
  }) async {
    _error = null;
    _setLoading(true);
    try {
      await _api.updatePrivacy(
        avatarVisibility: avatarVisibility,
        bioVisibility: bioVisibility,
        lastSeenVisibility: lastSeenVisibility,
      );
      _privacy = <String, String>{
        'avatarVisibility': avatarVisibility ?? _privacy['avatarVisibility']!,
        'bioVisibility': bioVisibility ?? _privacy['bioVisibility']!,
        'lastSeenVisibility':
            lastSeenVisibility ?? _privacy['lastSeenVisibility']!,
      };
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _error = null;
    _setLoading(true);
    try {
      await _api.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadSessions() async {
    _error = null;
    _setLoading(true);
    try {
      _sessions = await _api.getMySessions();
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> revokeSession(String sessionId) async {
    _error = null;
    _setLoading(true);
    try {
      await _api.revokeMySession(sessionId);
      _sessions = _sessions
          .map((entry) {
            if ((entry['id'] ?? '') == sessionId) {
              return <String, dynamic>{
                ...entry,
                'revokedAt': DateTime.now().toUtc().toIso8601String(),
              };
            }
            return entry;
          })
          .toList(growable: false);
    } on ApiError catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> _applySession(
    AuthSession session, {
    required bool setActive,
    required bool notify,
  }) async {
    final mutable = List<StoredAccount>.from(_accounts);
    final index = mutable.indexWhere(
      (entry) => entry.session.user.id == session.user.id,
    );
    if (index >= 0) {
      mutable[index] = StoredAccount(session: session);
    } else {
      if (mutable.length >= 3) {
        mutable.removeLast();
      }
      mutable.insert(0, StoredAccount(session: session));
    }
    _accounts = mutable;
    if (setActive) {
      _activeSession = session;
    }
    await _store.saveAccounts(_accounts, _activeSession?.user.id);
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _replaceCurrentUser(AuthUser user) async {
    final current = _activeSession;
    if (current == null) {
      return;
    }
    final updatedSession = AuthSession(
      accessToken: current.accessToken,
      refreshToken: current.refreshToken,
      user: user,
    );
    _activeSession = updatedSession;
    _accounts = _accounts
        .map((entry) {
          if (entry.session.user.id == user.id) {
            return StoredAccount(session: updatedSession);
          }
          return entry;
        })
        .toList(growable: false);
    await _store.saveAccounts(_accounts, user.id);
  }

  Future<void> _loadSettingsSnapshot() async {
    final payload = await _api.getMyProfile();
    final user = AuthUser.fromJson(
      (payload['user'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    );
    final privacyRaw =
        (payload['privacy'] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    _privacy = <String, String>{
      'avatarVisibility': (privacyRaw['avatarVisibility'] ?? 'everyone')
          .toString(),
      'bioVisibility': (privacyRaw['bioVisibility'] ?? 'everyone').toString(),
      'lastSeenVisibility': (privacyRaw['lastSeenVisibility'] ?? 'contacts')
          .toString(),
    };
    _sessions = await _api.getMySessions();
    await _replaceCurrentUser(user);
  }

  List<StoredAccount> _deduplicateAccounts(List<StoredAccount> source) {
    final seen = <int>{};
    final result = <StoredAccount>[];
    for (final entry in source) {
      final userId = entry.session.user.id;
      if (seen.add(userId)) {
        result.add(entry);
      }
    }
    return result;
  }

  void _clearRuntimeData({bool keepAuth = false}) {
    _currentTab = CtrlTab.home;
    _chats = const [];
    _contacts = const [];
    _calls = const [];
    _selectedChatId = null;
    _messagesByChat.clear();
    _searchByScope.clear();
    _privacy = const <String, String>{
      'avatarVisibility': 'everyone',
      'bioVisibility': 'everyone',
      'lastSeenVisibility': 'contacts',
    };
    _sessions = const <Map<String, dynamic>>[];
    _searchScope = 'messages';
    _searchQuery = '';
    _loginChallengeId = null;
    _registerFlowToken = null;
    _devCodeHint = null;
    _pendingEmail = null;
    _replyToMessageId = null;
    _voiceHoldMode = false;
    _videoNoteMode = false;
    if (!keepAuth) {
      _activeSession = null;
    }
  }

  void _setLoading(bool value) {
    _loading = value;
  }
}
