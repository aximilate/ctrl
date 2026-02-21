import 'package:shared_preferences/shared_preferences.dart';

import '../models/entities.dart';

class SessionStore {
  static const _accountsKey = 'ctrlchat.accounts.v1';
  static const _activeUserIdKey = 'ctrlchat.active_user_id.v1';

  Future<List<StoredAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) {
      return const <StoredAccount>[];
    }
    try {
      return StoredAccount.decodeList(raw);
    } catch (_) {
      return const <StoredAccount>[];
    }
  }

  Future<int?> loadActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_activeUserIdKey);
  }

  Future<void> saveAccounts(
    List<StoredAccount> accounts,
    int? activeUserId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, StoredAccount.encodeList(accounts));
    if (activeUserId == null) {
      await prefs.remove(_activeUserIdKey);
      return;
    }
    await prefs.setInt(_activeUserIdKey, activeUserId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountsKey);
    await prefs.remove(_activeUserIdKey);
  }
}
