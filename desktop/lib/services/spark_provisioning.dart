import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'firebase_api.dart';

class SparkProvisioning {
  static final _deptId = RegExp(r'^dept[1-9][0-9]{0,11}$');

  static Future<void> _checkEnabled() async {
    try {
      await FirebaseApi.database(['sparkProvisioning']);
    } on FirebaseApiException catch (error) {
      if (!error.accessDenied) rethrow;
      throw const FirebaseApiException(
          'Department setup requires administrator access and the current Firebase rules.');
    }
  }

  static String _name(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 80) {
      throw const FirebaseApiException(
          'Enter a department name of up to 80 characters.');
    }
    return name;
  }

  static Future<String> createDepartment(String value) async {
    final name = _name(value);
    await _checkEnabled();
    for (var attempt = 0; attempt < 5; attempt++) {
      final snapshots = [
        await FirebaseApi.database(['departments'])
      ];
      final occupied = <int>{};
      for (final snapshot in snapshots.whereType<Map>()) {
        for (final id
            in snapshot.keys.whereType<String>().where(_deptId.hasMatch)) {
          final number = int.parse(id.substring(4));
          occupied.add(number);
        }
      }
      var available = 1;
      while (occupied.contains(available)) {
        available++;
      }
      final id = 'dept$available';
      if (!_deptId.hasMatch(id)) break;
      final random = Random.secure();
      final generation = List.generate(
              16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      try {
        if (await FirebaseApi.createOnly([
          'departments',
          id
        ], {
          'name': name,
          'mode': 'college',
          'generation': generation,
          'config': {'ringDurationSec': 5, 'timezone': 'IST'},
        })) {
          return id;
        }
      } on FirebaseApiException catch (error) {
        // Rules can deny the create when a concurrent request claimed the ID.
        if (!error.accessDenied ||
            await FirebaseApi.database(['departments', id]) == null) {
          rethrow;
        }
      }
    }
    throw const FirebaseApiException(
        'Could not reserve a department ID. Refresh and try again.');
  }

  static Future<void> renameDepartment(String id, String name) async {
    _checkId(id);
    await FirebaseApi.database(['departments', id, 'name'],
        method: 'PUT', body: _name(name));
  }

  static void _checkId(String id) {
    if (!_deptId.hasMatch(id)) {
      throw const FirebaseApiException(
          'Select a department added through this app.');
    }
  }

  static Future<http.Response> _auth(String action, Map<String, Object> body) {
    final apiKey = Firebase.app().options.apiKey;
    return http
        .post(
          Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:$action',
              {'key': apiKey}),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<void> createSecretary(
      String id, String email, String password) async {
    _checkId(id);
    final address = email.trim().toLowerCase();
    if (address.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address) ||
        password.length < 12 ||
        password.length > 128) {
      throw const FirebaseApiException(
          'Enter a valid email and an initial password of 12 to 128 characters.');
    }
    await _checkEnabled();
    final department = await FirebaseApi.database(['departments', id]);
    if (department is! Map || department['name'] is! String) {
      throw const FirebaseApiException(
          'Department not found. Refresh and try again.');
    }
    // This REST request does not replace the admin's app or Windows session.
    final signup = await _auth('signUp',
        {'email': address, 'password': password, 'returnSecureToken': true});
    final response = jsonDecode(signup.body);
    if (signup.statusCode != 200) {
      final code = response is Map && response['error'] is Map
          ? response['error']['message']
          : null;
      throw FirebaseApiException(code == 'EMAIL_EXISTS'
          ? 'An account with this email already exists. Use a different address or ask your Firebase administrator to check it.'
          : 'Firebase could not create the login. Check the email and password and try again.');
    }
    if (response is! Map ||
        response['localId'] is! String ||
        response['idToken'] is! String) {
      throw const FirebaseApiException(
          'Firebase returned an unexpected response. Ask your Firebase administrator to check the new account.');
    }
    final path = ['users', response['localId'] as String];
    try {
      await FirebaseApi.database(path, method: 'PUT', body: {
        'role': 'secretary',
        'departments': {id: true},
        'managedDepartment': id,
        if (department['generation'] case final String generation)
          'departmentGeneration': generation,
      });
      return;
    } on FirebaseApiException catch (error) {
      if (!error.accessDenied) {
        throw const FirebaseApiException(
            'The login was created, but the assignment could not be confirmed. Ask your Firebase administrator to check it before retrying.');
      }
      try {
        final cleanup =
            await _auth('delete', {'idToken': response['idToken'] as String});
        if (cleanup.statusCode == 200) {
          throw const FirebaseApiException(
              'Firebase denied the department assignment. The new login was removed.');
        }
      } on FirebaseApiException {
        rethrow;
      } catch (_) {
        // Report the account as incomplete. No profile means no bell access.
      }
    } catch (_) {
      throw const FirebaseApiException(
          'The login was created, but the assignment could not be confirmed. Ask your Firebase administrator to check it before retrying.');
    }
    throw const FirebaseApiException(
        'Could not finish setting up this login. Ask your Firebase administrator to check the account before retrying.');
  }
}
