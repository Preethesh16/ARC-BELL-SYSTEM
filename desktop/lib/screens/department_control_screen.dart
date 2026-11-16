import 'package:flutter/material.dart';

import '../services/department_service.dart';
import '../services/firebase_api.dart';
import '../widgets/bell_page.dart';

class DepartmentControlScreen extends StatefulWidget {
  final String dept;
  final String? departmentName;
  final bool managed;
  final DepartmentService? service;
  const DepartmentControlScreen(
      {super.key,
      required this.dept,
      this.departmentName,
      this.managed = false,
      this.service});

  @override
  State<DepartmentControlScreen> createState() =>
      _DepartmentControlScreenState();
}

class _DepartmentControlScreenState extends State<DepartmentControlScreen> {
  static const _modes = {
    'college': 'College day',
    'exam': 'Exam day',
    'holiday': 'Holiday'
  };
  late final _service = widget.service ?? DepartmentService();
  String? _mode;
  List<int> _times = [];
  bool _busy = false;
  String? _error;
  String get _name => widget.departmentName ?? widget.dept.toUpperCase();

  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _load() async {
    final mode = await _service.getMode(widget.dept, managed: widget.managed);
    final times =
        await _service.getSchedule(widget.dept, mode, managed: widget.managed);
    if (mounted) {
      setState(() {
        _mode = mode;
        _times = times;
      });
    }
  }

  Future<void> _run(Future<void> Function() action,
      {bool reloadAfterFailure = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      if (reloadAfterFailure) {
        try {
          await _load();
        } catch (_) {
          if (mounted) setState(() => _mode = null);
        }
      }
      if (mounted) {
        setState(() => _error = error is FirebaseApiException
            ? error.message
            : 'The request did not complete. Check your connection before trying again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
          String title, String description, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(title),
                content: Text(description),
                actions: [
                  TextButton(
                      autofocus: true,
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(action)),
                ],
              )) ??
      false;

  Future<void> _ring() => _run(() async {
        final confirmed = await _confirm(
            'Ring the bell in $_name?',
            'People in this department may hear the bell immediately.',
            'Send Ring Command');
        if (!confirmed || !mounted) return;
        await _service.triggerManualRing(widget.dept, managed: widget.managed);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Ring command sent. This does not confirm the bell sounded.'),
          ));
        }
      });

  Future<void> _selectMode(String next) => _run(() async {
        if (!await _confirm(
                'Switch to ${_modes[next]}?',
                'This changes the active bell schedule for $_name.',
                'Switch Schedule') ||
            !mounted) {
          return;
        }
        await _service.setMode(widget.dept, next, managed: widget.managed);
        await _load();
      }, reloadAfterFailure: true);

  Future<void> _addTime() => _run(() async {
        final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
            helpText: 'Add a bell time');
        if (picked == null || !mounted) return;
        final minutes = picked.hour * 60 + picked.minute;
        if (_times.contains(minutes)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('That time is already in the schedule.')));
          return;
        }
        await _service.addTime(widget.dept, _mode!, minutes,
            managed: widget.managed);
        await _load();
      }, reloadAfterFailure: true);

  String _format(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  Future<void> _removeTime(int minutes) => _run(() async {
        if (!await _confirm(
                'Remove the ${_format(minutes)} bell?',
                'This time will be removed from the active schedule for $_name.',
                'Remove Time') ||
            !mounted) {
          return;
        }
        await _service.deleteTime(widget.dept, _mode!, minutes,
            managed: widget.managed);
        await _load();
      }, reloadAfterFailure: true);

  @override
  Widget build(BuildContext context) {
    final active = _mode;
    final ready = active != null && !_busy;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scheduleName =
        _modes[active] ?? (active == null ? 'Loading…' : active);
    final refresh = OutlinedButton.icon(
      onPressed: _busy ? null : () => _run(_load),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Refresh schedule'),
      style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white54)),
    );

    final schedule = _ControlPanel(
      icon: Icons.schedule_outlined,
      title: 'Scheduled bell times',
      subtitle: 'Editing: $scheduleName',
      action: FilledButton.icon(
        onPressed: ready ? _addTime : null,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Time'),
      ),
      child: _times.isEmpty
          ? Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  radius: 24,
                  child: const Icon(Icons.event_available_outlined),
                ),
                const SizedBox(height: 12),
                Text('No times scheduled',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Select Add Time to schedule the first bell.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant)),
              ]),
            )
          : Column(children: [
              for (final (index, minutes) in _times.indexed) ...[
                if (index > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(Icons.schedule_outlined, color: colors.primary),
                  title: Text(_format(minutes),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: IconButton(
                    tooltip: 'Remove ${_format(minutes)}',
                    onPressed: ready ? () => _removeTime(minutes) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ]),
    );

    final controls =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _ControlPanel(
        icon: Icons.calendar_month_outlined,
        title: 'Active schedule',
        subtitle: 'Choose which schedule the bell follows.',
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Schedule mode'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isDense: true,
              isExpanded: true,
              value: _modes.containsKey(active) ? active : null,
              hint: const Text('Choose a mode'),
              items: [
                for (final mode in _modes.entries)
                  DropdownMenuItem(value: mode.key, child: Text(mode.value)),
              ],
              onChanged: ready
                  ? (next) {
                      if (next != null && next != active) _selectMode(next);
                    }
                  : null,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      _ControlPanel(
        icon: Icons.notifications_outlined,
        title: 'Manual bell',
        subtitle: 'Use only when you need the bell to sound immediately.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: ready ? _ring : null,
            style: OutlinedButton.styleFrom(foregroundColor: colors.error),
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Ring Now'),
          ),
        ),
      ),
    ]);

    return BellPage(
      label: 'Department workspace',
      pageIcon: Icons.event_note_outlined,
      title: _name,
      description:
          'Manage scheduled times and bell controls for this department.',
      back: true,
      accountAction: refresh,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12)
        ],
        if (_error != null) ...[
          Semantics(
              liveRegion: true,
              child: BellNotice(
                icon: Icons.error_outline,
                title: 'Could not complete the request',
                detail: _error!,
              )),
          const SizedBox(height: 12),
        ],
        if (active != null)
          LayoutBuilder(builder: (context, bounds) {
            if (bounds.maxWidth < 760) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    schedule,
                    const SizedBox(height: 16),
                    controls,
                  ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: schedule),
              const SizedBox(width: 20),
              Expanded(flex: 3, child: controls),
            ]);
          }),
      ]),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget child;

  const _ControlPanel(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.action,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text.rich(
                  TextSpan(children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(icon, size: 20, color: colors.primary),
                      ),
                    ),
                    TextSpan(text: title),
                  ]),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          child,
        ]),
      ),
    );
  }
}
