import 'package:flutter/material.dart';

class BellPage extends StatelessWidget {
  final String label;
  final String title;
  final String description;
  final Widget child;
  final Widget? actions;
  final Widget? accountAction;
  final bool back;
  final IconData pageIcon;

  const BellPage({
    super.key,
    required this.label,
    required this.title,
    required this.description,
    required this.child,
    this.actions,
    this.accountAction,
    this.back = false,
    this.pageIcon = Icons.dashboard_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: back,
        actions: [
          if (accountAction != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: accountAction!,
            ),
        ],
        title: Row(children: [
          Image.asset('assets/logo.png',
              height: 36, excludeFromSemantics: true),
          const SizedBox(width: 12),
          const Flexible(
              child: Text(
            'ARC College Bell',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          )),
        ]),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: SizedBox(
              height: 2,
              width: double.infinity,
              child: ColoredBox(color: Color(0xFFB5985C))),
        ),
      ),
      body: LayoutBuilder(builder: (context, viewport) {
        final content = SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(label.toUpperCase(),
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colors.primary,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w700,
                                    )),
                                const SizedBox(height: 9),
                                Semantics(
                                    header: true,
                                    child: Text(title,
                                        style: theme.textTheme.headlineLarge
                                            ?.copyWith(
                                          height: 1.15,
                                          fontWeight: FontWeight.w700,
                                        ))),
                                const SizedBox(height: 8),
                                Text(description,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                        color: colors.onSurfaceVariant)),
                                if (actions != null) ...[
                                  const SizedBox(height: 20),
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: actions!),
                                ],
                              ])),
                          if (viewport.maxWidth >= 740) ...[
                            const SizedBox(width: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(14)),
                              child: Icon(pageIcon,
                                  color: colors.primary, size: 32),
                            ),
                          ],
                        ]),
                  ),
                  const SizedBox(height: 20),
                  child,
                ]),
          )),
        );
        if (viewport.maxWidth < 1000) return content;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: 198, child: _WorkspaceRail(label: label, icon: pageIcon)),
          Expanded(child: content),
        ]);
      }),
    );
  }
}

class _WorkspaceRail extends StatelessWidget {
  final String label;
  final IconData icon;
  const _WorkspaceRail({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 30, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CAMPUS OPERATIONS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  )),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: colors.primary, fontWeight: FontWeight.w600))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class BellSignOut extends StatelessWidget {
  final VoidCallback? onPressed;
  const BellSignOut({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white54,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.logout, size: 17),
        label: const Text('Sign out'),
      );
}

class BellNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  const BellNotice(
      {super.key,
      required this.icon,
      required this.title,
      required this.detail,
      this.action});

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      ));
}
