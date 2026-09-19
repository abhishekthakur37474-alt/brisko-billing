import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../../core/utils/result.dart';
import '../../../settings/domain/repositories/settings_repository.dart';

/// Securely verifies and sets the manager password.
class ManagerAuthService {
  const ManagerAuthService({required this.settings});

  static const String keyManagerPassword = 'auth.manager_password';

  final SettingsRepository settings;

  /// Verifies the provided plaintext password against the stored hash.
  /// 
  /// Returns `true` if the password is correct or if no manager password has been set yet.
  Future<Result<bool>> verifyPassword(String plaintext) async {
    final Result<String?> stored = await settings.readString(keyManagerPassword);
    if (stored.isErr) {
      return Err<bool>(stored.failureOrNull!);
    }

    final String? storedHash = stored.valueOrNull;
    if (storedHash == null || storedHash.isEmpty) {
      // If no password is set, we return true so the manager can set it up,
      // or we can reject. Let's reject, to be secure.
      return Ok<bool>(false);
    }

    final List<String> parts = storedHash.split(':');
    if (parts.length != 2) {
      return Ok<bool>(false); // Corrupt hash
    }

    final String salt = parts[0];
    final String hash = parts[1];

    final String computed = _hashPassword(plaintext, salt);
    return Ok<bool>(computed == hash);
  }

  /// Sets the manager password, hashing it securely.
  Future<Result<void>> setPassword(String plaintext) async {
    final String salt = _generateSalt();
    final String hash = _hashPassword(plaintext, salt);
    return settings.writeString(keyManagerPassword, '$salt:$hash');
  }
  
  Future<Result<bool>> isPasswordSet() async {
    final Result<String?> stored = await settings.readString(keyManagerPassword);
    if (stored.isErr) {
      return Err<bool>(stored.failureOrNull!);
    }
    final String? storedHash = stored.valueOrNull;
    return Ok<bool>(storedHash != null && storedHash.isNotEmpty);
  }

  String _generateSalt() {
    final Random random = Random.secure();
    final List<int> saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64.encode(saltBytes);
  }

  String _hashPassword(String password, String salt) {
    final List<int> bytes = utf8.encode('$salt$password');
    final Digest digest = sha256.convert(bytes);
    return digest.toString();
  }
}
