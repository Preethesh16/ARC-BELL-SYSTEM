import 'dart:convert';

import 'package:college_bell/services/windows_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeVault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

http.Response reply(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  test(
      'remembered sign-in survives a fresh process, rotates and clears on sign-out',
      () async {
    final vault = FakeVault();
    var clock = DateTime(2026, 1, 1);
    var refreshCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('signInWithPassword')) {
        return reply({
          'idToken': 'id-first',
          'localId': 'uid',
          'refreshToken': 'refresh-first',
          'expiresIn': '3600'
        });
      }
      refreshCalls++;
      expect(request.url.host, 'securetoken.googleapis.com');
      expect(request.bodyFields['refresh_token'],
          refreshCalls == 1 ? 'refresh-first' : 'refresh-rotated');
      return reply({
        'id_token': 'id-$refreshCalls',
        'user_id': 'uid',
        'refresh_token': 'refresh-rotated',
        'expires_in': '3600'
      });
    });
    WindowsSession launch() => WindowsSession(
        vault: vault,
        client: client,
        apiKey: () => 'mock-key',
        now: () => clock);
    final first = launch();
    await first.signIn('test@example.test', 'TestOnlyPassword!',
        remember: true);
    expect(vault.value, isNull);
    await first.commit();
    expect(vault.value, 'refresh-first');

    final next = launch();
    expect(await next.restore(), 'uid');
    expect(vault.value, 'refresh-rotated');
    expect(await next.token(), 'id-1');
    clock = clock.add(const Duration(hours: 1));
    expect(await Future.wait([next.token(), next.token()]), ['id-2', 'id-2']);
    expect(refreshCalls, 2);
    await next.signOut();
    expect(await launch().restore(), isNull);
  });

  test(
      'an unavailable network preserves the saved session; a revoked token clears it',
      () async {
    final vault = FakeVault()..value = 'refresh';
    var result = reply({}, 503);
    final session = WindowsSession(
        vault: vault,
        client: MockClient((_) async => result),
        apiKey: () => 'mock-key');
    await expectLater(session.restore(), throwsA(isA<SessionException>()));
    expect(vault.value, 'refresh');
    result = reply({
      'error': {'message': 'TOKEN_EXPIRED'}
    }, 400);
    expect(await session.restore(), isNull);
    expect(vault.value, isNull);
  });

  test('shared computer sign-in stores no refresh token', () async {
    final vault = FakeVault()..value = 'older-session';
    final session = WindowsSession(
        vault: vault,
        client: MockClient((_) async => reply({
              'idToken': 'temporary',
              'localId': 'uid',
              'refreshToken': 'private',
              'expiresIn': '3600'
            })),
        apiKey: () => 'mock-key');
    await session.signIn('temp@example.test', 'TestOnlyPassword!',
        remember: false);
    await session.commit();
    expect(vault.value, isNull);
    expect(await session.token(), 'temporary');
  });
}
