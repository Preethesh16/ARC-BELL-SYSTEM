import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/windows_session.dart';

class LoginScreen extends StatefulWidget {
  final Future<Map<String, dynamic>?> Function(String, String,
      {required bool remember})? onSignIn;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final String? notice;
  const LoginScreen(
      {super.key, this.onSignIn, required this.onAuthenticated, this.notice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _visible = false;
  bool _remember = true;
  String? _message;

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final profile = await (widget.onSignIn ?? AuthService().login)(
        _email.text.trim(),
        _password.text,
        remember: _remember,
      );
      if (!mounted) return;
      if (profile == null) {
        setState(() => _message =
            'Your login is valid, but bell access has not been assigned. Contact your administrator.');
      } else {
        widget.onAuthenticated(profile);
      }
    } on SessionException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not sign in. Check your connection and try again.');
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(body: LayoutBuilder(builder: (context, bounds) {
      final wide = bounds.maxWidth >= 850;
      return Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                  flex: wide ? 5 : 1,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(wide ? 40 : 22),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF10263F), Color(0xFF244D70)],
                        )),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/logo.png',
                              width: wide ? 76 : 50,
                              semanticLabel: 'College logo'),
                          const SizedBox(height: 20),
                          const Text('CAMPUS ADMINISTRATION',
                              style: TextStyle(
                                  color: Color(0xFFE3CE9C),
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('ARC College Bell',
                              style: theme.textTheme.displaySmall?.copyWith(
                                  color: Colors.white,
                                  letterSpacing: -1.5,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text(
                              'Campus bell schedules and department access in one place.',
                              style: TextStyle(
                                  color: Color(0xFFE1E8F1), fontSize: 17)),
                          if (wide) ...[
                            const SizedBox(height: 24),
                            const Divider(color: Color(0xFF687D93)),
                            const SizedBox(height: 12),
                            const Text('College staff portal',
                                style: TextStyle(
                                    color: Color(0xFFE3CE9C),
                                    fontWeight: FontWeight.w600)),
                          ],
                        ]),
                  )),
              SizedBox(width: wide ? 28 : 0, height: wide ? 0 : 16),
              Flexible(
                  flex: wide ? 4 : 1,
                  child: Card(
                    child: Padding(
                        padding: EdgeInsets.all(wide ? 32 : 24),
                        child: Form(
                          key: _form,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Staff sign-in',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                const Text(
                                    'Use the account given to you by the college.'),
                                const SizedBox(height: 20),
                                TextFormField(
                                    controller: _email,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                        labelText: 'Email address',
                                        prefixIcon: Icon(Icons.mail_outline)),
                                    validator: (value) =>
                                        !(value ?? '').trim().contains('@')
                                            ? 'Enter your email address.'
                                            : null),
                                const SizedBox(height: 14),
                                TextFormField(
                                    controller: _password,
                                    enabled: !_busy,
                                    obscureText: !_visible,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon:
                                            const Icon(Icons.lock_outline),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                              () => _visible = !_visible),
                                          tooltip: _visible
                                              ? 'Hide password'
                                              : 'Show password',
                                          icon: Icon(_visible
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined),
                                        )),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Enter your password.'
                                            : null),
                                if (AuthService.isWindows)
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                        'Keep me signed in on this PC'),
                                    subtitle: const Text(
                                        'Uncheck on a shared computer.'),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: _remember,
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                            setState(() => _remember = value!),
                                  ),
                                if (_message != null || widget.notice != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Text(_message ?? widget.notice!,
                                            style: TextStyle(
                                                color:
                                                    theme.colorScheme.error))),
                                  ),
                                const SizedBox(height: 16),
                                FilledButton(
                                    onPressed: _busy ? null : _submit,
                                    child: Text(
                                        _busy ? 'Signing in…' : 'Sign in')),
                              ]),
                        )),
                  )),
            ],
          ),
        ),
      ));
    }));
  }
}
