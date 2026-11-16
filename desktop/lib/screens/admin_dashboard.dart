import 'package:flutter/material.dart';

import '../services/department_service.dart';
import '../widgets/bell_page.dart';
import 'department_control_screen.dart';
import 'manage_departments_screen.dart';

class AdminDashboard extends StatefulWidget {
  final Future<void> Function() onSignOut;
  final DepartmentService? service;
  const AdminDashboard({super.key, required this.onSignOut, this.service});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final _service = widget.service ?? DepartmentService();
  late Future<List<Department>> _departments = _service.getDepartments();
  String _filter = '';
  bool _signingOut = false;

  void _reload() {
    final next = _service.getDepartments();
    setState(() {
      _departments = next;
    });
  }

  Future<void> _manage({bool add = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ManageDepartmentsScreen(service: _service, addOnOpen: add),
    ));
    if (mounted) _reload();
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not clear the saved session. Try signing out again.')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => BellPage(
        label: 'Administration',
        pageIcon: Icons.apartment_outlined,
        title: 'Departments',
        description:
            'Choose a department to view its bell and schedule. Use Manage Departments to set up secretary logins.',
        accountAction: BellSignOut(onPressed: _signingOut ? null : _logout),
        actions: Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
              onPressed: () => _manage(add: true),
              icon: const Icon(Icons.add),
              label: const Text('Add Department')),
          OutlinedButton.icon(
              onPressed: () => _manage(),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Manage Departments')),
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
                  detail: 'Check your connection and try again.',
                  action: FilledButton(
                      onPressed: _reload, child: const Text('Retry')));
            }
            final departments = snapshot.data!;
            final visible = departments
                .where(
                    (d) => '${d.name} ${d.id}'.toLowerCase().contains(_filter))
                .toList();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                            child: TextFormField(
                                onChanged: (value) => setState(
                                    () => _filter = value.trim().toLowerCase()),
                                decoration: const InputDecoration(
                                    labelText: 'Find a department',
                                    prefixIcon: Icon(Icons.search)))),
                        const SizedBox(width: 12),
                        IconButton.outlined(
                            onPressed: _reload,
                            tooltip: 'Refresh departments',
                            icon: const Icon(Icons.refresh)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('${visible.length} of ${departments.length} departments',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (visible.isEmpty)
                    BellNotice(
                        icon: Icons.apartment_outlined,
                        title: departments.isEmpty
                            ? 'No departments yet'
                            : 'No matching departments',
                        detail: departments.isEmpty
                            ? 'Use Add Department to get started.'
                            : 'Try a different department name or ID.'),
                  DepartmentCards(departments: visible),
                ]);
          },
        ),
      );
}

class DepartmentCards extends StatelessWidget {
  final List<Department> departments;
  const DepartmentCards({super.key, required this.departments});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 940 && departments.length >= 3
              ? 3
              : width >= 620
                  ? 2
                  : 1;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final department in departments)
              SizedBox(
                width: (width - 16 * (columns - 1)) / columns,
                child: DepartmentTile(department: department),
              ),
          ]);
        },
      );
}

class DepartmentTile extends StatelessWidget {
  final Department department;
  const DepartmentTile({super.key, required this.department});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final icon = department.id == 'icbs'
        ? Icons.functions
        : department.name.toLowerCase() == 'physics'
            ? Icons.science_outlined
            : Icons.apartment_outlined;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: colors.onPrimaryContainer),
          ),
        ),
        title: Text(department.name,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text('Open bell and schedule',
            style: TextStyle(color: colors.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right, color: colors.primary),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DepartmentControlScreen(
            dept: department.id,
            departmentName: department.name,
            managed: department.managed,
          ),
        )),
      ),
    );
  }
}
