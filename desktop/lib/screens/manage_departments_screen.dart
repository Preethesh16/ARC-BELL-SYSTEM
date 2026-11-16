import 'dart:async';

import 'package:flutter/material.dart';

import '../services/department_service.dart';
import '../services/firebase_api.dart';
import '../services/windows_session.dart';
import '../widgets/bell_page.dart';

class ManageDepartmentsScreen extends StatefulWidget {
  final DepartmentService service;
  final bool addOnOpen;

  const ManageDepartmentsScreen(
      {super.key, required this.service, this.addOnOpen = false});

  @override
  State<ManageDepartmentsScreen> createState() =>
      _ManageDepartmentsScreenState();
}

class _ManageDepartmentsScreenState extends State<ManageDepartmentsScreen> {
  late Future<List<Department>> _departments;

  @override
  void initState() {
    super.initState();
    _departments = widget.service.getDepartments();
    if (widget.addOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _edit();
      });
    }
  }

  void _reload() {
    final refreshed = widget.service.getDepartments();
    setState(() {
      _departments = refreshed;
    });
  }

  Future<void> _edit([Department? department]) async {
    final edited = await showDialog<Department>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DepartmentEditor(
        service: widget.service,
        department: department,
      ),
    );
    if (!mounted) return;
    _reload();
    if (department == null && edited != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${edited.name}.')),
      );
    }
  }

  Future<void> _secretary(Department department) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SecretaryEditor(service: widget.service, department: department),
    );
    if (mounted && done == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Secretary login created for ${department.name}.')),
      );
    }
  }

  Future<void> _delete(Department department) async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteDepartmentDialog(
        department: department,
        service: widget.service,
      ),
    );
    if (!mounted) return;
    _reload();
    if (deleted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${department.name} removed. Its ID is reserved until account and controller cleanup.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => BellPage(
        label: 'Administration',
        pageIcon: Icons.settings_outlined,
        title: 'Manage Departments',
        description:
            'Set up new departments, update their display names, and create secretary logins.',
        back: true,
        actions: Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Add Department')),
          OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh')),
        ]),
        child: FutureBuilder<List<Department>>(
          future: _departments,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return BellNotice(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load departments',
                  detail: _error(snapshot.error!),
                  action: FilledButton(
                      onPressed: _reload, child: const Text('Retry')));
            }
            if (snapshot.data!.isEmpty) {
              return const BellNotice(
                  icon: Icons.apartment_outlined,
                  title: 'No departments yet.',
                  detail: 'Select Add Department to set up your first one.');
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final dept in snapshot.data!)
                    Card(
                        child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                child: Icon(dept.managed
                                    ? Icons.apartment_outlined
                                    : Icons.school_outlined),
                              ),
                              title: Text(dept.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(dept.managed
                                  ? 'Department ID: ${dept.id}'
                                  : '${dept.id} · Existing setup'),
                            ),
                            if (dept.managed)
                              Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                        onPressed: () => _edit(dept),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Rename')),
                                    FilledButton.tonalIcon(
                                        onPressed: () => _secretary(dept),
                                        icon: const Icon(
                                            Icons.person_add_outlined),
                                        label: const Text(
                                            'Create Secretary Login')),
                                    TextButton.icon(
                                        onPressed: () => _delete(dept),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Delete')),
                                  ]),
                          ]),
                    )),
                ]);
          },
        ),
      );
}

String _error(Object error) {
  if (error is FirebaseApiException) return error.message;
  if (error is SessionException) return error.message;
  if (error is TimeoutException) {
    return 'The request timed out. Refresh and check whether it completed before retrying.';
  }
  return 'Could not reach Firebase. Check your connection and try again.';
}

class _DeleteDepartmentDialog extends StatefulWidget {
  final Department department;
  final DepartmentService service;
  const _DeleteDepartmentDialog(
      {required this.department, required this.service});

  @override
  State<_DeleteDepartmentDialog> createState() =>
      _DeleteDepartmentDialogState();
}

class _DeleteDepartmentDialogState extends State<_DeleteDepartmentDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _deleting = false;
  String? _message;

  Future<void> _submit() async {
    if (_deleting || !_form.currentState!.validate()) return;
    final password = _password.text;
    _password.clear();
    setState(() {
      _deleting = true;
      _message = null;
    });
    try {
      await widget.service.deleteDepartment(widget.department.id, password);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _message = error is FirebaseApiException && error.accessDenied
            ? 'Firebase blocked deletion. Check your permissions and whether a ring request is pending.'
            : _error(error);
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        scrollable: true,
        icon: Icon(Icons.warning_amber_rounded, color: colors.error),
        title: Text('Delete ${widget.department.name}?'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'This permanently removes the department and its schedules. Its secretaries lose department access. A Firebase project operator must remove their login accounts and confirm the controller is retired before this ID can be reused.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  enabled: !_deleting,
                  decoration:
                      const InputDecoration(labelText: 'Your account password'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your password to continue.'
                      : null,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                      liveRegion: true,
                      child: Text(_message!,
                          style: TextStyle(color: colors.error))),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: _deleting ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: colors.error, foregroundColor: colors.onError),
            onPressed: _deleting ? null : _submit,
            child: Text(_deleting ? 'Deleting…' : 'Delete Department'),
          ),
        ],
      ),
    );
  }
}

class _DepartmentEditor extends StatefulWidget {
  final DepartmentService service;
  final Department? department;

  const _DepartmentEditor({required this.service, this.department});

  @override
  State<_DepartmentEditor> createState() => _DepartmentEditorState();
}

class _DepartmentEditorState extends State<_DepartmentEditor> {
  late final _name = TextEditingController(text: widget.department?.name);
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _withSecretary = false;
  Department? _created;
  String? _message;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final current = widget.department;
      final name = _name.text.trim();
      if (current != null) {
        await widget.service.renameDepartment(current.id, name);
        if (mounted) {
          Navigator.pop(context, Department(current.id, name, managed: true));
        }
      } else {
        final dept = await widget.service.createDepartment(name);
        if (!mounted) return;
        if (!_withSecretary) {
          Navigator.pop(context, dept);
          return;
        }
        // The department already exists. A failed login can be retried here
        // or later without allocating a second department.
        setState(() {
          _created = dept;
          _saving = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _error(error);
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    if (created != null) {
      return _SecretaryEditor(
          service: widget.service, department: created, returnDepartment: true);
    }
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        icon: Icon(widget.department == null
            ? Icons.add_business_outlined
            : Icons.edit_outlined),
        title: Text(
            widget.department == null ? 'Add Department' : 'Rename Department'),
        content: SizedBox(
            width: 410,
            child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _name,
                      autofocus: true,
                      enabled: !_saving,
                      maxLength: 80,
                      decoration:
                          const InputDecoration(labelText: 'Department name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a department name.'
                              : null,
                      onFieldSubmitted: (_) => _save(),
                    ),
                    if (widget.department == null)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _withSecretary,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                setState(() => _withSecretary = value!),
                        title:
                            const Text('Create a secretary login after saving'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    if (_message != null)
                      Text(_message!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ],
                ))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save Department')),
        ],
      ),
    );
  }
}

class _SecretaryEditor extends StatefulWidget {
  final DepartmentService service;
  final Department department;
  final bool returnDepartment;

  const _SecretaryEditor(
      {required this.service,
      required this.department,
      this.returnDepartment = false});

  @override
  State<_SecretaryEditor> createState() => _SecretaryEditorState();
}

class _SecretaryEditorState extends State<_SecretaryEditor> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _message;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.createSecretary(
          widget.department.id, _email.text.trim(), _password.text);
      if (!mounted) return;
      _password.clear();
      Navigator.pop(
          context, widget.returnDepartment ? widget.department : true);
    } catch (error) {
      if (!mounted) return;
      _password.clear();
      setState(() {
        _message = _error(error);
        _saving = false;
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          icon: const Icon(Icons.person_add_outlined),
          scrollable: true,
          title: const Text('Create Secretary Login'),
          content: SizedBox(
              width: 410,
              child: Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.returnDepartment
                          ? '${widget.department.name} was created. You can set up its secretary now or come back later.'
                          : 'This account can access only ${widget.department.name}.'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _email,
                        autofocus: true,
                        enabled: !_saving,
                        keyboardType: TextInputType.emailAddress,
                        decoration:
                            const InputDecoration(labelText: 'Secretary email'),
                        validator: (value) =>
                            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(value?.trim() ?? '')
                                ? 'Enter a valid email address.'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        enabled: !_saving,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Initial password',
                            helperText:
                                '12 to 128 characters. No email will be sent.'),
                        validator: (value) =>
                            (value?.length ?? 0) < 12 || value!.length > 128
                                ? 'Use 12 to 128 characters.'
                                : null,
                        onFieldSubmitted: (_) => _save(),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(_message!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ))),
          actions: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.pop(context,
                      widget.returnDepartment ? widget.department : null),
              child: Text(
                  widget.returnDepartment ? 'Finish Without Login' : 'Cancel'),
            ),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Creating…' : 'Create Login')),
          ],
        ),
      );
}
