import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class FirebaseApiException implements Exception {
  final String message;
  final bool accessDenied;
  const FirebaseApiException(this.message, {this.accessDenied = false});
  @override
  String toString() => message;
}

class FirebaseApi {
  static const databaseUrl = String.fromEnvironment(
    'BELL_DATABASE_URL',
  );

  static Future<String> token() => AuthService.idToken();

  static Future<dynamic> database(
    List<String> path, {
    String method = 'GET',
    Object? body,
    String? confirmedToken,
  }) async {
    final endpoint = await _endpoint(path, confirmedToken: confirmedToken);
    final res = await (method == 'PUT'
            ? http.put(endpoint,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body))
            : http.get(endpoint))
        .timeout(const Duration(seconds: 15));
    _check(res);
    return jsonDecode(res.body);
  }

  static Future<Uri> _endpoint(List<String> path,
      {String? confirmedToken}) async {
    if (databaseUrl.isEmpty) {
      throw const FirebaseApiException('The database URL is missing from this build.');
    }
    final base = Uri.parse(databaseUrl);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((part) => part.isNotEmpty),
        ...path.take(path.length - 1),
        '${path.last}.json',
      ],
      queryParameters: {
        ...base.queryParameters,
        'auth': confirmedToken ?? await token()
      },
    );
  }

  static void _check(http.Response res) {
    if (res.statusCode != 200) {
      final denied = res.statusCode == 401 || res.statusCode == 403;
      throw FirebaseApiException(
          denied
              ? 'Firebase denied access. Check your account permissions.'
              : 'Firebase is unavailable. Try again.',
          accessDenied: denied);
    }
  }

  static Future<void> updateSchedule(
    List<String> path,
    Object? Function(dynamic current) update,
  ) async {
    final endpoint = await _endpoint(path);
    for (var attempt = 0; attempt < 4; attempt++) {
      final current = await http.get(endpoint, headers: {
        'X-Firebase-ETag': 'true'
      }).timeout(const Duration(seconds: 10));
      _check(current);
      final etag = current.headers['etag'];
      if (etag == null) {
        throw const FirebaseApiException(
            'Could not check the current schedule.');
      }
      final res = await http
          .put(
            endpoint,
            headers: {'Content-Type': 'application/json', 'If-Match': etag},
            body: jsonEncode(update(jsonDecode(current.body))),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 412) continue;
      _check(res);
      return;
    }
    throw const FirebaseApiException(
        'Someone else changed the schedule. Refresh and try again.');
  }

  static Future<bool> createOnly(List<String> path, Object body) async {
    final res = await http
        .put(
          await _endpoint(path),
          headers: {
            'Content-Type': 'application/json',
            'If-Match': 'null_etag'
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 412) return false;
    _check(res);
    return true;
  }
}
