import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/fly_localizations.dart';
import '../../files/presentation/file_entry_content.dart';
import '../domain/sync_protocol.dart';
import '../services/file_transfer_inventory.dart';
import 'sync_controller.dart';

Future<void> showSyncStatusDetails(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(sheet).height * .8,
      child: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: SyncStatusDetails(),
      ),
    ),
  );
}

class SyncStatusDetails extends ConsumerStatefulWidget {
  const SyncStatusDetails({super.key});
  @override
  ConsumerState<SyncStatusDetails> createState() => _SyncStatusDetailsState();
}

class _SyncStatusDetailsState extends ConsumerState<SyncStatusDetails>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _refreshing = false, _loaded = false;
  int _pending = 0;
  FileTransferInventory _files = const FileTransferInventory();
  DateTime? _lastSuccess;
  String? _readError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    unawaited(_refresh());
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final sync = ref.read(syncControllerProvider);
    try {
      final pending = await sync.outbox.pendingRecordCount();
      final files = await FileTransferInventory.load(sync.outbox.db, sync.root);
      final cursor = sync.connectionMode == SyncConnectionMode.lan
          ? 'lanCursor'
          : 'cloudCursor';
      final saved = await sync.outbox.state(
        await sync.outbox.successStateKey(cursor),
      );
      if (mounted) {
        setState(() {
          _pending = pending;
          _files = files;
          _loaded = true;
          _readError = null;
          _lastSuccess = DateTime.tryParse(saved ?? '');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _readError = '$error';
          _loaded = true;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider), engine = sync.engine;
    final zh = context.l10n.isZh;
    String text(String a, String b) => zh ? a : b;
    final transfer = engine?.files;
    final last = engine?.lastSuccess ?? _lastSuccess;
    final error = engine?.error ?? sync.error ?? _readError;
    final permitted =
        sync.connectionMode == SyncConnectionMode.lan || sync.cloudFiles;
    return Column(
      key: const ValueKey('sync-status-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text('同步状态', 'Sync status'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              sync.connected ? Icons.devices_outlined : Icons.link_off_outlined,
              color: sync.connected
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(engine?.status ?? text('未连接', 'Disconnected')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text(
            '绿色表示连接或同步周期成功；文件是否已到本机，请查看下面的队列。',
            'Green indicates a connected or successful sync cycle. File availability is shown below.',
          ),
        ),
        if (!_loaded)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 12),
        for (final entry in [
          ('changes', text('待发送记录', 'Pending records'), _pending),
          (
            'uploads',
            text('待发送／确认文件', 'Files awaiting upload/check'),
            _files.uploads,
          ),
          ('downloads', text('待下载文件', 'Pending downloads'), _files.downloads),
          (
            'source',
            text('其中等待源设备', 'Waiting for source'),
            _files.waitingForSource > (transfer?.waiting ?? 0)
                ? _files.waitingForSource
                : transfer?.waiting ?? 0,
          ),
        ])
          ListTile(
            key: ValueKey('sync-pending-${entry.$1}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(entry.$2),
            trailing: Text('${entry.$3}'),
          ),
        if (!permitted)
          Text(
            text(
              '云同步仅传输数据，以下文件数量为本机待通过本地同步传输的内容。',
              'Cloud sync transfers records only. File counts below need local sync for content.',
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (engine?.running == true && transfer != null) ...[
          const SizedBox(height: 8),
          Text(
            '${text('文件检查', 'File checks')}: ${transfer.completed}/${transfer.total}',
          ),
          if (transfer.currentFile != null)
            Text(
              transfer.currentFile!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (transfer.phase == 'uploading' ||
              transfer.phase == 'downloading') ...[
            Text(
              transfer.phase == 'uploading'
                  ? text('正在上传', 'Uploading')
                  : text('正在下载', 'Downloading'),
            ),
            LinearProgressIndicator(
              key: const ValueKey('sync-file-progress'),
              value: transfer.bytesTotal == 0
                  ? null
                  : (transfer.bytesTransferred / transfer.bytesTotal).clamp(
                      0.0,
                      1.0,
                    ),
            ),
            Text(
              '${fileSizeLabel(transfer.bytesTransferred)} / ${fileSizeLabel(transfer.bytesTotal)}',
            ),
          ],
        ],
        const SizedBox(height: 12),
        Text(
          '${text('最近成功', 'Last success')}: ${last == null ? text('尚无成功记录', 'Never') : DateFormat('yyyy-MM-dd HH:mm:ss').format(last.toLocal())}',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              '${text('原因', 'Reason')}: $error',
              key: const ValueKey('sync-status-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if ((engine?.consecutiveFailures ?? 0) >= 3)
          Text(
            text(
              '连续失败 3 次，已停止重试。可点击下面的按钮重新连接。',
              'Stopped after 3 failures. Reconnect below.',
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('sync-details-connect'),
              onPressed: sync.busy || sync.connecting
                  ? null
                  : () async {
                      await sync.connectNow();
                      if (mounted) await _refresh();
                    },
              icon: const Icon(Icons.sync),
              label: Text(
                sync.connected
                    ? text('立即同步', 'Sync now')
                    : text('立即连接', 'Connect now'),
              ),
            ),
            TextButton(
              onPressed: _refreshing ? null : _refresh,
              child: Text(text('刷新状态', 'Refresh status')),
            ),
          ],
        ),
      ],
    );
  }
}
