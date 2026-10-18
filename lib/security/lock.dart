// Logowanie do aplikacji: PIN, wzór, blokada ekranu telefonu, opcjonalnie biometria.
// Sekret nie jest zapisywany – tylko solony skrót (wielokrotny SHA-256).

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LockMethod { none, pin, pattern, device }

class LockConfig {
  final LockMethod method;
  final bool biometric;
  final int timeoutSec; // po jakim czasie w tle wymagać ponownego logowania
  const LockConfig(this.method, this.biometric, this.timeoutSec);
}

class Lock {
  static const _kMethod = 'lock_method';
  static const _kHash = 'lock_hash';
  static const _kSalt = 'lock_salt';
  static const _kBio = 'lock_bio';
  static const _kTimeout = 'lock_timeout';
  static const _kFails = 'lock_fails';
  static const _kUntil = 'lock_until';
  static const _kPinLen = 'lock_pin_len';
  static const _iterations = 20000;

  static Future<LockConfig> load() async {
    final p = await SharedPreferences.getInstance();
    var m = p.getString(_kMethod);
    // zgodność ze starszą wersją (przełącznik blokady ekranem telefonu)
    if (m == null && (p.getBool('lock') ?? false)) m = LockMethod.device.name;
    final method = LockMethod.values.firstWhere((e) => e.name == m, orElse: () => LockMethod.none);
    return LockConfig(method, p.getBool(_kBio) ?? false, p.getInt(_kTimeout) ?? 60);
  }

  static String _hash(String secret, String salt) {
    List<int> h = utf8.encode('$salt|$secret');
    for (var i = 0; i < _iterations; i++) {
      h = sha256.convert([...h, ...utf8.encode(salt)]).bytes;
    }
    return base64Encode(h);
  }

  static Future<void> setSecret(LockMethod method, String secret) async {
    final p = await SharedPreferences.getInstance();
    final r = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await p.setString(_kSalt, salt);
    await p.setString(_kHash, _hash(secret, salt));
    await p.setString(_kMethod, method.name);
    await p.remove('lock');
    if (method == LockMethod.pin) {
      await p.setInt(_kPinLen, secret.length);
    } else {
      await p.remove(_kPinLen);
    }
    await resetFailures();
  }

  /// Długość PIN-u – pozwala odblokować bez zatwierdzania (null dla PIN-ów ustawionych w wersji 1.0.22).
  static Future<int?> pinLength() async => (await SharedPreferences.getInstance()).getInt(_kPinLen);
  static Future<void> rememberPinLength(int n) async => (await SharedPreferences.getInstance()).setInt(_kPinLen, n);

  static Future<void> setMethod(LockMethod method) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMethod, method.name);
    await p.remove('lock');
    if (method == LockMethod.none || method == LockMethod.device) {
      await p.remove(_kHash);
      await p.remove(_kSalt);
      await p.setBool(_kBio, false);
    }
  }

  static Future<void> setBiometric(bool v) async => (await SharedPreferences.getInstance()).setBool(_kBio, v);
  static Future<void> setTimeout(int sec) async => (await SharedPreferences.getInstance()).setInt(_kTimeout, sec);

  static Future<bool> verify(String secret) async {
    final p = await SharedPreferences.getInstance();
    final salt = p.getString(_kSalt), hash = p.getString(_kHash);
    if (salt == null || hash == null) return false;
    final ok = _hash(secret, salt) == hash;
    if (ok) {
      await resetFailures();
    } else {
      final f = (p.getInt(_kFails) ?? 0) + 1;
      await p.setInt(_kFails, f);
      // od 5. błędnej próby rosnąca blokada: 30 s, 60 s, 120 s…
      if (f >= 5) {
        final wait = 30 * pow(2, f - 5).toInt().clamp(1, 32);
        await p.setInt(_kUntil, DateTime.now().add(Duration(seconds: wait)).millisecondsSinceEpoch);
      }
    }
    return ok;
  }

  static Future<void> resetFailures() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFails);
    await p.remove(_kUntil);
  }

  /// Ile sekund trzeba jeszcze odczekać po błędnych próbach.
  static Future<int> waitSeconds() async {
    final p = await SharedPreferences.getInstance();
    final u = p.getInt(_kUntil);
    if (u == null) return 0;
    final s = (u - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
    return s > 0 ? s + 1 : 0;
  }

  static Future<int> failures() async => (await SharedPreferences.getInstance()).getInt(_kFails) ?? 0;

  static final _auth = LocalAuthentication();

  static Future<bool> biometricAvailable() async {
    try {
      return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deviceAuthAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Biometria (tylko odcisk/twarz) albo blokada ekranu telefonu ([biometricOnly] = false).
  static Future<bool> systemAuth({required bool biometricOnly, String reason = 'Odblokuj Teczkę Zdrowia'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(biometricOnly: biometricOnly, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
