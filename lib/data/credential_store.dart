import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CredentialStore {
  CredentialStore._();

  static const _credKey = 'webdav_cred';
  static const _saltKey = 'webdav_salt';

  static Future<String> _salt() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_saltKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final fresh = base64Encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await prefs.setString(_saltKey, fresh);
    return fresh;
  }

  static String _deriveKey(String salt) {
    final bytes = utf8.encode('diary_webdav_v1_$salt');
    return sha256.convert(bytes).toString();
  }

  static String _obfuscate(String plain, String key) {
    final keyBytes = utf8.encode(key);
    final plainBytes = utf8.encode(plain);
    final masked = List<int>.generate(plainBytes.length, (i) {
      return plainBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return base64Encode(masked);
  }

  static String _deobfuscate(String encoded, String key) {
    final masked = base64Decode(encoded);
    final keyBytes = utf8.encode(key);
    final plain = List<int>.generate(masked.length, (i) {
      return masked[i] ^ keyBytes[i % keyBytes.length];
    });
    return utf8.decode(plain);
  }

  static Future<void> savePassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (password.isEmpty) {
      await prefs.remove(_credKey);
      return;
    }
    final salt = await _salt();
    final derived = _deriveKey(salt);
    final obfuscated = _obfuscate(password, derived);
    await prefs.setString(_credKey, obfuscated);
  }

  static Future<String> loadPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_credKey);
    if (encoded == null || encoded.isEmpty) {
      return '';
    }
    final salt = await _salt();
    final derived = _deriveKey(salt);
    try {
      return _deobfuscate(encoded, derived);
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credKey);
  }
}
