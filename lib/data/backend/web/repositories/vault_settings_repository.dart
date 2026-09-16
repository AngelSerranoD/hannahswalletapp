import '../../../../domain/repositories/repositories.dart';
import 'vault_session.dart';

class VaultSettingsRepository implements SettingsRepository {
  VaultSettingsRepository(this._session);

  final VaultSession _session;

  @override
  Future<Map<String, String>> getAll() async =>
      Map<String, String>.of(_session.data.settings);

  @override
  Future<String?> get(String key) async => _session.data.settings[key];

  @override
  Future<void> set(String key, String value) async {
    _session.data.settings[key] = value;
    _session.touch();
  }

  @override
  Future<bool> getBool(String key, {bool fallback = false}) async {
    final String? raw = _session.data.settings[key];
    if (raw == null) return fallback;
    return raw.toLowerCase() == 'true' || raw == '1';
  }

  @override
  Future<void> setBool(String key, bool value) =>
      set(key, value ? 'true' : 'false');
}
