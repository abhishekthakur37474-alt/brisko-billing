import '../../../../core/utils/result.dart';

/// Read and write access to POS configuration.
///
/// A typed façade over a key/value table. Callers ask for a string, an int or a
/// bool and never parse stored text themselves, which keeps the interpretation of a
/// setting in one place.
///
/// Not a `LocalStore`: settings have no id, no soft delete and no per-row sync
/// state, so forcing them through the syncable entity contract would add three
/// meaningless columns.
abstract interface class SettingsRepository {
  Future<Result<String?>> readString(String key);

  Future<Result<int?>> readInt(String key);

  /// Reads a boolean. Anything other than the stored value `true` is false.
  Future<Result<bool>> readBool(String key, {bool defaultValue = false});

  Future<Result<void>> writeString(String key, String value);

  Future<Result<void>> writeInt(String key, int value);

  Future<Result<void>> writeBool(String key, bool value);

  /// Every setting, for the settings screen and for diagnostics.
  Future<Result<Map<String, String?>>> readAll();

  Future<Result<void>> remove(String key);
}
