import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/dashboard_focus_board.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import 'task_providers.dart';

/// The task workspace owns the Focus Board entry; existing focus data is reused.
class TaskFocusPage extends ConsumerStatefulWidget {
  const TaskFocusPage({super.key});

  @override
  ConsumerState<TaskFocusPage> createState() => _TaskFocusPageState();
}

class _TaskFocusPageState extends ConsumerState<TaskFocusPage> {
  bool historyOpen = false;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(localTodayProvider);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) => Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: DashboardFocusBoard(
                        day: day,
                        onHistory: () => setState(() => historyOpen = true),
                      ),
                    ),
                  ),
                ),
              ),
              if (historyOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => historyOpen = false),
                    child: ColoredBox(
                      color: context.flyColors.textPrimary.withValues(
                        alpha: .08,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: math.min(390, bounds.maxWidth),
                  child: DashboardFocusHistoryPanel(
                    onClose: () => setState(() => historyOpen = false),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
