import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/account/presentation/local_profile_avatar.dart';
import '../../l10n/fly_localizations.dart';
import '../../shared/design_system/design_tokens.dart';
import '../../shared/design_system/fly_color_scheme.dart';
import '../settings/navigation_settings.dart';
import '../settings/settings_center.dart';

enum PrimaryModule {
  dashboard,
  customers,
  orders,
  tasks,
  calendar,
  matrix,
  files,
  notes,
  tools,
}

PrimaryModule primaryModuleForPath(String path) {
  if (path.startsWith('/dashboard')) return PrimaryModule.dashboard;
  if (path.startsWith('/customers')) return PrimaryModule.customers;
  if (path.startsWith('/orders')) return PrimaryModule.orders;
  if (path.startsWith('/calendar')) return PrimaryModule.calendar;
  if (path.startsWith('/matrix')) return PrimaryModule.matrix;
  if (path.startsWith('/files')) return PrimaryModule.files;
  if (path.startsWith('/notes') || path.startsWith('/knowledge')) {
    return PrimaryModule.notes;
  }
  if (path.startsWith('/tools')) return PrimaryModule.tools;
  return PrimaryModule.tasks;
}

class PrimaryNavigationRail extends ConsumerWidget {
  const PrimaryNavigationRail({
    required this.selectedModule,
    required this.onSelected,
    super.key,
  });

  final PrimaryModule selectedModule;
  final ValueChanged<PrimaryModule> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      key: const ValueKey('primary-navigation-rail'),
      color: context.flyColors.primaryRail,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FlySpacing.sm),
          child: Column(
            children: [
              const LocalProfileAvatar(),
              const SizedBox(height: FlySpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: FlySpacing.lg),
                      if (ref
                          .watch(navigationSettingsProvider)
                          .value
                          .dashboardVisible)
                        NavigationRailItem(
                          module: PrimaryModule.dashboard,
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home_rounded,
                          tooltip: 'Dashboard',
                          selected: selectedModule == PrimaryModule.dashboard,
                          onTap: () => onSelected(PrimaryModule.dashboard),
                        ),
                      const SizedBox(height: FlySpacing.xs),
                      if (ref
                          .watch(navigationSettingsProvider)
                          .value
                          .crmVisible)
                        NavigationRailItem(
                          module: PrimaryModule.customers,
                          icon: Icons.people_outline,
                          selectedIcon: Icons.people,
                          tooltip: context.l10n.t('navCustomers'),
                          selected: selectedModule == PrimaryModule.customers,
                          onTap: () => onSelected(PrimaryModule.customers),
                        ),
                      const SizedBox(height: FlySpacing.xs),
                      if (ref
                          .watch(navigationSettingsProvider)
                          .value
                          .crmVisible)
                        NavigationRailItem(
                          module: PrimaryModule.orders,
                          icon: Icons.receipt_long_outlined,
                          selectedIcon: Icons.receipt_long,
                          tooltip: context.l10n.t('navOrders'),
                          selected: selectedModule == PrimaryModule.orders,
                          onTap: () => onSelected(PrimaryModule.orders),
                        ),
                      const SizedBox(height: FlySpacing.xs),
                      NavigationRailItem(
                        module: PrimaryModule.tasks,
                        icon: Icons.check_box_outlined,
                        selectedIcon: Icons.check_box,
                        tooltip: context.l10n.t('tasks'),
                        selected: selectedModule == PrimaryModule.tasks,
                        onTap: () => onSelected(PrimaryModule.tasks),
                      ),
                      const SizedBox(height: FlySpacing.xs),
                      NavigationRailItem(
                        module: PrimaryModule.calendar,
                        icon: Icons.calendar_month_outlined,
                        selectedIcon: Icons.calendar_month,
                        tooltip: context.l10n.t('calendar'),
                        selected: selectedModule == PrimaryModule.calendar,
                        onTap: () => onSelected(PrimaryModule.calendar),
                      ),
                      const SizedBox(height: FlySpacing.xs),
                      NavigationRailItem(
                        module: PrimaryModule.matrix,
                        icon: Icons.grid_view_outlined,
                        selectedIcon: Icons.grid_view,
                        tooltip: context.l10n.t('matrix'),
                        selected: selectedModule == PrimaryModule.matrix,
                        onTap: () => onSelected(PrimaryModule.matrix),
                      ),
                      const SizedBox(height: FlySpacing.xs),
                      NavigationRailItem(
                        module: PrimaryModule.files,
                        icon: Icons.folder_outlined,
                        selectedIcon: Icons.folder,
                        tooltip: context.l10n.t('navFiles'),
                        selected: selectedModule == PrimaryModule.files,
                        onTap: () => onSelected(PrimaryModule.files),
                      ),
                      const SizedBox(height: FlySpacing.xs),
                      if (ref
                          .watch(navigationSettingsProvider)
                          .value
                          .knowledgeVisible)
                        NavigationRailItem(
                          module: PrimaryModule.notes,
                          icon: Icons.menu_book_outlined,
                          selectedIcon: Icons.menu_book_rounded,
                          tooltip: context.l10n.t('navNotes'),
                          selected: selectedModule == PrimaryModule.notes,
                          onTap: () => onSelected(PrimaryModule.notes),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 28, child: Divider()),
              const SizedBox(height: FlySpacing.xs),
              if (ref.watch(navigationSettingsProvider).value.toolsVisible)
                NavigationRailItem(
                  module: PrimaryModule.tools,
                  icon: Icons.handyman_outlined,
                  selectedIcon: Icons.handyman_rounded,
                  tooltip: context.l10n.t('tools'),
                  selected: selectedModule == PrimaryModule.tools,
                  onTap: () => onSelected(PrimaryModule.tools),
                ),
              const SizedBox(height: FlySpacing.sm),
              _SettingsMenu(ref: ref),
            ],
          ),
        ),
      ),
    );
  }
}

class NavigationRailItem extends StatefulWidget {
  const NavigationRailItem({
    required this.module,
    required this.icon,
    required this.selectedIcon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final PrimaryModule module;
  final IconData icon;
  final IconData selectedIcon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<NavigationRailItem> createState() => _NavigationRailItemState();
}

class _NavigationRailItemState extends State<NavigationRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hover = context.flyColors.hover;
    final selected = context.flyColors.selected;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.tooltip,
          child: InkWell(
            key: ValueKey('primary-${widget.module.name}'),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(FlyRadius.md),
            child: AnimatedContainer(
              duration: FlyMotion.fast,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.selected
                    ? selected
                    : (_hovered ? hover : Colors.transparent),
                borderRadius: BorderRadius.circular(FlyRadius.md),
                boxShadow: widget.selected && !dark
                    ? const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 5,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.selected ? widget.selectedIcon : widget.icon,
                size: FlyMetrics.iconLg,
                color: widget.selected
                    ? context.flyColors.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.ref});
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('primary-settings'),
    tooltip: context.l10n.t('settings'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const SettingsCenter(),
    ),
    icon: const Icon(Icons.settings_outlined, size: FlyMetrics.iconLg),
  );
}
