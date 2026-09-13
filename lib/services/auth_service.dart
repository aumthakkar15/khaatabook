import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../models/models.dart';
import 'currency_service.dart';
import 'category_service.dart';
import 'session.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Feature 1 & 2: on-device accounts (salted, iterated SHA-256 hash) and
/// fingerprint login. Nothing leaves the phone.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _iterations = 20000;
  static const _prefBioUser = 'biometric_login_id';
  static const _prefLastUser = 'last_login_id';

  String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  String _hash(String password, String salt) {
    List<int> bytes = utf8.encode('$salt::$password');
    for (var i = 0; i < _iterations; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64.encode(bytes);
  }

  Future<bool> hasAnyUser() async {
    final rows = await (await AppDb.instance.db).rawQuery('SELECT COUNT(*) c FROM users');
    return (rows.first['c'] as int) > 0;
  }

  Future<String?> lastLoginId() async => (await SharedPreferences.getInstance()).getString(_prefLastUser);

  Future<User> register({
    required String name,
    required String loginId,
    required String password,
    required String country,
    required String baseCurrency,
  }) async {
    if (name.trim().isEmpty) throw AuthException('Please enter your name');
    if (loginId.trim().length < 3) throw AuthException('Login ID must be at least 3 characters');
    if (password.length < 6) throw AuthException('Password must be at least 6 characters');
    final d = await AppDb.instance.db;
    final exists = await d.query('users', where: 'login_id = ? COLLATE NOCASE', whereArgs: [loginId.trim()]);
    if (exists.isNotEmpty) throw AuthException('That login ID is already used on this phone');
    final salt = _salt();
    final u = User(
      name: name.trim(),
      loginId: loginId.trim(),
      passwordHash: _hash(password, salt),
      salt: salt,
      country: country,
      baseCurrency: baseCurrency,
    );
    final id = await d.insert('users', u.toMap()..remove('id'));
    final user = User.fromMap((await d.query('users', where: 'id = ?', whereArgs: [id])).first);

    // First-run seeding: currency master + default categories + a cash wallet.
    await CurrencyService.instance.seedIfEmpty(baseCurrency);
    await CategoryService.instance.seedDefaultsIfEmpty();
    final accounts = await d.query('accounts', limit: 1);
    if (accounts.isEmpty) {
      await d.insert('accounts', Account(name: 'Wallet', type: AccountType.cash, currency: baseCurrency).toMap()..remove('id'));
    }
    await _remember(user);
    Session.instance.signIn(user);
    return user;
  }

  Future<User> login(String loginId, String password) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('users', where: 'login_id = ? COLLATE NOCASE', whereArgs: [loginId.trim()]);
    if (rows.isEmpty) throw AuthException('No account with that login ID on this phone');
    final u = User.fromMap(rows.first);
    if (_hash(password, u.salt) != u.passwordHash) throw AuthException('Incorrect password');
    await _remember(u);
    Session.instance.signIn(u);
    return u;
  }

  Future<void> _remember(User u) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefLastUser, u.loginId);
  }

  Future<void> changePassword(String current, String next) async {
    final u = Session.instance.user!;
    if (_hash(current, u.salt) != u.passwordHash) throw AuthException('Current password is incorrect');
    if (next.length < 6) throw AuthException('New password must be at least 6 characters');
    final salt = _salt();
    final d = await AppDb.instance.db;
    await d.update('users', {'password_hash': _hash(next, salt), 'salt': salt}, where: 'id = ?', whereArgs: [u.id]);
    Session.instance.update(User.fromMap((await d.query('users', where: 'id = ?', whereArgs: [u.id])).first));
  }

  /// Verifies the signed-in user's password (used before sensitive actions).
  bool verifyPassword(String password) {
    final u = Session.instance.user!;
    return _hash(password, u.salt) == u.passwordHash;
  }

  // ---------- Biometric (fingerprint) ----------
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> biometricAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final can = await _auth.canCheckBiometrics;
      if (!supported || !can) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Login ID that has fingerprint login enabled on this phone (if any).
  Future<String?> biometricUser() async => (await SharedPreferences.getInstance()).getString(_prefBioUser);

  Future<void> setBiometric(bool enabled) async {
    final u = Session.instance.user!;
    final p = await SharedPreferences.getInstance();
    if (enabled) {
      final ok = await _prompt('Confirm your fingerprint to enable quick login');
      if (!ok) throw AuthException('Fingerprint not confirmed');
      await p.setString(_prefBioUser, u.loginId);
    } else {
      await p.remove(_prefBioUser);
    }
    final d = await AppDb.instance.db;
    await d.update('users', {'biometric': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [u.id]);
    Session.instance.update(User.fromMap((await d.query('users', where: 'id = ?', whereArgs: [u.id])).first));
  }

  Future<User> loginWithBiometric() async {
    final loginId = await biometricUser();
    if (loginId == null) throw AuthException('Fingerprint login is not enabled yet. Sign in with your password first.');
    final ok = await _prompt('Sign in to Khaata Book');
    if (!ok) throw AuthException('Fingerprint not recognised');
    final d = await AppDb.instance.db;
    final rows = await d.query('users', where: 'login_id = ? COLLATE NOCASE', whereArgs: [loginId]);
    if (rows.isEmpty) throw AuthException('Account not found');
    final u = User.fromMap(rows.first);
    await _remember(u);
    Session.instance.signIn(u);
    return u;
  }

  Future<bool> _prompt(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  void signOut() => Session.instance.signOut();
}
