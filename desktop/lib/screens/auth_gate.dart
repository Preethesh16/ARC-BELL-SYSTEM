import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/bell_page.dart';
import 'admin_dashboard.dart';
import 'login_screen.dart';
import 'secretary_dashboard.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  late Future<Map<String, dynamic>?> _restore;
  Map<String, dynamic>? _profile;
  bool _signedOut = false;

  @override
  void initState() {
    super.initState();
    _restore = _auth.restoreSavedSession();
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    setState(() {
      _profile = null;
      _signedOut = true;
    });
  }

  Widget _login() => LoginScreen(
      onAuthenticated: (profile) => setState(() => _profile = profile));

  Widget _dashboard(Map<String, dynamic> profile) {
    final role = profile['role'];
    if (role == 'admin' || role == 'superadmin') {
      return AdminDashboard(onSignOut: _logout);
    }
    return SecretaryDashboard(userData: profile, onSignOut: _logout);
  }

  @override
  Widget build(BuildContext context) {
    if (_profile != null) return _dashboard(_profile!);
    if (_signedOut) return _login();
    return FutureBuilder<Map<String, dynamic>?>(
      future: _restore,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const BellPage(
            label: 'Staff access',
            title: 'Welcome back',
            description: 'Checking your saved session…',
            pageIcon: Icons.lock_outline,
            child: LinearProgressIndicator(
              semanticsLabel: 'Checking saved session',
            ),
          );
        }
        if (snapshot.hasError) {
          return BellPage(
            label: 'Sign in',
            pageIcon: Icons.cloud_off_outlined,
            title: 'Reconnect to College Bell',
            description: 'We couldn’t verify your saved session.',
            child: BellNotice(
              icon: Icons.cloud_off_outlined,
              title: 'Check your connection',
              detail:
                  'Retry to keep using your saved session, or sign out to use a different account.',
              action: Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton(
                    onPressed: () {
                      final next = _auth.restoreSavedSession();
                      setState(() {
                        _restore = next;
                      });
                    },
                    child: const Text('Retry')),
                OutlinedButton(
                    onPressed: () async {
                      try {
                        await _logout();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Windows could not clear the saved session.')));
                        }
                      }
                    },
                    child: const Text('Use another account')),
              ]),
            ),
          );
        }
        return snapshot.data == null ? _login() : _dashboard(snapshot.data!);
      },
    );
  }
}
