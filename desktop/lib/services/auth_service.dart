import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_api.dart';
import 'windows_session.dart';

class AuthService {
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static final windows = WindowsSession(
    vault: WindowsCredentialVault(),
    client: http.Client(),
    apiKey: () => Firebase.app().options.apiKey,
  );

  static Future<String> idToken() async {
    if (isWindows) return windows.token();
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) {
      throw const SessionException('Please sign in again.', expired: true);
    }
    return token;
  }

  Future<Map<String, dynamic>?> login(String email, String password,
      {required bool remember}) async {
    if (isWindows) {
      await windows.signIn(email, password, remember: remember);
    } else {
      if (kIsWeb) {
        await FirebaseAuth.instance
            .setPersistence(remember ? Persistence.LOCAL : Persistence.SESSION);
      }
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
    }
    try {
      final profile = await _profile(
          isWindows ? windows.uid : FirebaseAuth.instance.currentUser?.uid);
      if (profile == null) {
        await logout();
      } else if (isWindows) {
        await windows.commit();
      }
      return profile;
    } catch (_) {
      await logout();
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> restoreSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'password',
      'token',
      'tokenTimestamp',
      'loggedIn',
      'uid',
      'email',
      'role',
      'userData'
    ]) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
    final uid = isWindows
        ? await windows.restore()
        : (await FirebaseAuth.instance.authStateChanges().first).uidOrNull;
    final profile = await _profile(uid);
    if (uid != null && profile == null) await logout();
    return profile;
  }

  Future<Map<String, dynamic>?> _profile(String? uid) async {
    if (uid == null) return null;
    final data = await FirebaseApi.database(['users', uid]);
    if (data is! Map<String, dynamic> ||
        !const ['admin', 'superadmin', 'secretary'].contains(data['role'])) {
      return null;
    }
    return data;
  }

  Future<void> logout() =>
      isWindows ? windows.signOut() : FirebaseAuth.instance.signOut();
}

extension on User? {
  String? get uidOrNull => this?.uid;
}
