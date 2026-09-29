import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'note_providers.dart';
import '../../reviews/presentation/review_providers.dart';

class NoteCloseGuard extends ConsumerStatefulWidget {
  const NoteCloseGuard({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<NoteCloseGuard> createState() => _NoteCloseGuardState();
}

class _NoteCloseGuardState extends ConsumerState<NoteCloseGuard> {
  static const channel = MethodChannel('fly/window_lifecycle');
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method != 'prepareClose') throw MissingPluginException();
      for (final session in List.of(ref.read(reviewSessionsProvider).values)) {
        try {
          await session.flush();
        } catch (_) {
          return false;
        }
      }
      for (final session in List.of(ref.read(noteSessionsProvider).values)) {
        try {
          await session.flush();
        } catch (_) {
          if (!session.draftProtected) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('草稿写入失败，已取消关闭。请保留窗口并检查磁盘空间。')),
              );
            }
            return false;
          }
        }
      }
      return true;
    });
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
