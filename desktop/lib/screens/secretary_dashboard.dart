import 'package:flutter/material.dart';

import '../services/department_service.dart';
import '../widgets/bell_page.dart';
import 'department_control_screen.dart';

class SecretaryDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Future<void> Function() onSignOut;
  final DepartmentService? service;
  const SecretaryDashboard(
      {super.key,
      required this.userData,
      required this.onSignOut,
      this.service});

  @override
  State<SecretaryDashboard> createState() => _SecretaryDashboardState();
}

class _SecretaryDashboardState extends State<SecretaryDashboard> {
  late final _service = widget.service ?? DepartmentService();
  late Future<List<Department>> _departments = _load();
  bool _signingOut = false;

  Future<List<Department>> _load() async {
    final assignments = widget.userData['departments'];
    if (assignments is! Map) return [];
    return Future.wait([
      for (final entry in assignments.entries)
        if (entry.key is String && entry.value == true)
          _service.getAssignedDepartment(entry.key as String),
    ]);
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
        label: 'Department secretary',
        pageIcon: Icons.badge_outlined,
        title: 'Department workspace',
        description:
            'Manage the bell and schedule for your assigned department.',
        accountAction: BellSignOut(onPressed: _signingOut ? null : _logout),
        child: FutureBuilder<List<Department>>(
          future: _departments,
          builder: (_, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return BellNotice(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your department',
                  detail:
                      'Check your connection. If the problem continues, contact your administrator.',
                  action: FilledButton(
                      onPressed: () {
                        final next = _load();
                        setState(() {
                          _departments = next;
                        });
                      },
                      child: const Text('Retry')));
            }
            if (snapshot.data!.isEmpty) {
              return const BellNotice(
                  icon: Icons.apartment_outlined,
                  title: 'No departments assigned.',
                  detail:
                      'Ask your administrator to assign your department to this account.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final department in snapshot.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _DepartmentWorkspace(department: department),
                  ),
              ],
            );
          },
        ),
      );
}

class _DepartmentWorkspace extends StatelessWidget {
  final Department department;
  const _DepartmentWorkspace({required this.department});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hero = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142B47), Color(0xFF284B70)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF304B68),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            department.id == 'icbs'
                ? Icons.functions
                : department.name.toLowerCase() == 'physics'
                    ? Icons.science_outlined
                    : Icons.apartment_outlined,
            color: const Color(0xFFEDD9A9),
          ),
        ),
        const SizedBox(height: 26),
        Text('ASSIGNED DEPARTMENT',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFFEDD9A9),
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 7),
        Text(department.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 5),
        Text('Bell and schedule',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFDCE6F2),
            )),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF0DEB3),
            foregroundColor: const Color(0xFF142B47),
          ),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Open bell and schedule'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DepartmentControlScreen(
              dept: department.id,
              departmentName: department.name,
              managed: department.managed,
            ),
          )),
        ),
      ]),
    );
    final guide = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Workspace tools',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Available in your department workspace.',
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          const _WorkspaceTool(Icons.calendar_today_outlined, 'Schedule mode',
              'See which schedule is active.'),
          const Divider(),
          const _WorkspaceTool(Icons.schedule_outlined, 'Bell times',
              'Review or update scheduled times.'),
          const Divider(),
          const _WorkspaceTool(Icons.notifications_outlined, 'Manual bell',
              'Review and confirm before sending a command.'),
        ]),
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 730) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              const SizedBox(height: 16),
              guide,
            ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: hero),
        const SizedBox(width: 20),
        Expanded(flex: 4, child: guide),
      ]);
    });
  }
}

class _WorkspaceTool extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _WorkspaceTool(this.icon, this.title, this.description);

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description),
      );
}
