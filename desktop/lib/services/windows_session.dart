import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class SessionException implements Exception {
  final String message;
  final bool expired;
  const SessionException(this.message, {this.expired = false});
}

abstract class SessionVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class WindowsCredentialVault implements SessionVault {
  static const _channel = MethodChannel('college_bell/windows_session');

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');
  @override
  Future<void> write(String token) =>
      _channel.invokeMethod<void>('write', token);
  @override
  Future<void> clear() => _channel.invokeMethod<void>('clear');
}

class WindowsSession {
  WindowsSession(
      {required this.vault,
      required this.client,
      required this.apiKey,
      DateTime Function()? now})
      : now = now ?? DateTime.now;

  final SessionVault vault;
  final http.Client client;
  final String Function() apiKey;
  final DateTime Function() now;
  String? uid;
  String? _id;
  String? _refresh;
  DateTime? _expires;
  bool _remember = false;
  Future<String>? _refreshing;

  Future<void> signIn(String email, String password,
      {required bool remember}) async {
    final data = await _passwordSignIn(email, password);
    _set(data, refreshing: false);
    _remember = remember;
  }

  // Use a separate token for the sensitive request. Leave the saved session alone.
  Future<String> confirmPassword(String currentToken, String password) async {
    final segments = currentToken.split('.');
    if (segments.length != 3) {
      throw const SessionException('Please sign in again.', expired: true);
    }
    final claims = jsonDecode(utf8.decode(
      base64Url.decode(base64Url.normalize(segments[1])),
    ));
    if (claims is! Map ||
        claims['email'] is! String ||
        claims['sub'] is! String) {
      throw const SessionException('Please sign in again.', expired: true);
    }
    final fresh = await _passwordSignIn(claims['email'] as String, password);
    final idToken = fresh['idToken'];
    if (fresh['localId'] != claims['sub'] || idToken is! String) {
      throw const SessionException('Could not confirm the current account.');
    }
    return idToken;
  }

  Future<Map<String, dynamic>> _passwordSignIn(
      String email, String password) async {
    final response = await client
        .post(
          Uri.https('identitytoolkit.googleapis.com',
              '/v1/accounts:signInWithPassword', {'key': apiKey()}),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'returnSecureToken': true
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(response, signingIn: true);
  }

  Future<void> commit() async {
    if (_remember && _refresh != null) {
      await vault.write(_refresh!);
    } else {
      await vault.clear();
    }
  }

  Future<String?> restore() async {
    _id = uid = null;
    _expires = null;
    _refresh = await vault.read();
    if (_refresh == null) return null;
    _remember = true;
    try {
      await token();
      return uid;
    } on SessionException catch (error) {
      if (!error.expired) rethrow;
      await signOut();
      return null;
    }
  }

  Future<String> token() async {
    final pending = _refreshing;
    if (pending != null) return pending;
    if (_id != null &&
        _expires!.isAfter(now().add(const Duration(minutes: 1)))) {
      return _id!;
    }
    final next = _exchange();
    _refreshing = next;
    try {
      return await next;
    } finally {
      _refreshing = null;
    }
  }

  Future<String> _exchange() async {
    final refresh = _refresh;
    if (refresh == null) {
      throw const SessionException('Please sign in again.', expired: true);
    }
    final response = await client.post(
      Uri.https('securetoken.googleapis.com', '/v1/token', {'key': apiKey()}),
      body: {'grant_type': 'refresh_token', 'refresh_token': refresh},
    ).timeout(const Duration(seconds: 15));
    final data = _decode(response, signingIn: false);
    if (_refresh != refresh) {
      throw const SessionException('Please sign in again.', expired: true);
    }
    _set(data, refreshing: true);
    if (_remember && _refresh != refresh) await commit();
    return _id!;
  }

  void _set(Map<String, dynamic> data, {required bool refreshing}) {
    final id = data[refreshing ? 'id_token' : 'idToken'];
    final refresh = data[refreshing ? 'refresh_token' : 'refreshToken'];
    final user = data[refreshing ? 'user_id' : 'localId'];
    final seconds =
        int.tryParse('${data[refreshing ? 'expires_in' : 'expiresIn']}');
    if (id is! String ||
        refresh is! String ||
        user is! String ||
        seconds == null ||
        seconds <= 0) {
      throw const SessionException(
          'The sign-in service returned an unexpected response.');
    }
    _id = id;
    _refresh = refresh;
    uid = user;
    _expires = now().add(Duration(seconds: seconds));
  }

  Map<String, dynamic> _decode(http.Response response,
      {required bool signingIn}) {
    if (response.statusCode >= 500) {
      throw const SessionException(
          'The sign-in service is unavailable. Try again.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    final error = data['error'];
    final code = error is Map ? error['message'] : null;
    const expired = {
      'TOKEN_EXPIRED',
      'USER_DISABLED',
      'USER_NOT_FOUND',
      'INVALID_REFRESH_TOKEN',
      'INVALID_GRANT'
    };
    if (!signingIn && expired.contains(code)) {
      throw const SessionException('Your saved session has expired.',
          expired: true);
    }
    throw SessionException(signingIn && code == 'USER_DISABLED'
        ? 'This account is disabled. Contact your administrator.'
        : signingIn &&
                [
                  'INVALID_LOGIN_CREDENTIALS',
                  'INVALID_PASSWORD',
                  'EMAIL_NOT_FOUND',
                  'INVALID_EMAIL'
                ].contains(code)
            ? 'The email or password is incorrect.'
            : 'Could not connect to the sign-in service. Try again shortly.');
  }

  Future<void> signOut() async {
    final pending = _refreshing;
    _id = _refresh = uid = null;
    _expires = null;
    _remember = false;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {/* Discard the in-flight refresh. */}
    }
    await vault.clear();
  }
}
