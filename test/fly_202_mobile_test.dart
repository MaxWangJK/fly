import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/calendar/presentation/mobile_calendar_workspace.dart';
import 'package:fly/features/calendar/presentation/mobile_calendar_drag.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/thumbnail_cache.dart';
import 'package:fly/features/files/presentation/file_entry_content.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/attachments/attachment_providers.dart';
import 'package:fly/shared/attachments/attachment_storage.dart';

class _Opener extends PlatformAttachmentOpener {
  final paths = <String>[];
  @override
  Future<void> open(String path) async => paths.add(path);
}

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('phone CRM, files, calendar and My page at $size', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-202-ui-'),
      ))!;
      final opener = _Opener();
      Map<dynamic, dynamic>? shared;
      var shareResult = 'synthetic-receiver';
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
            expect(call.method, 'share');
            shared = call.arguments as Map;
            return shareResult;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, null),
      );
      late String customerId, orderId, childListId, scheduledId;
      late File thumbnail;
      await tester.runAsync(() async {
        await db.ensureBuiltInData();
        final customer = await DriftCustomerRepository(db)
            .createCustomer(name: 'Desktop customer without follow-up date');
        customerId = customer.id;
        final order = await DriftOrderRepository(db)
            .createOrder(customerId: customer.id);
        orderId = order.id;
        final now = DateTime.now();
        final repo = DriftTaskRepository(db);
        final parent = await repo.createList('Work project');
        childListId = (await repo.createList(
          'Deliveries',
          parentId: parent.id,
        )).id;
        await repo.createTask(title: 'Nested list task', listId: childListId);
        final task = await repo.createTask(
          title: 'Scheduled task',
          dueDate: DateTime(now.year, now.month, now.day, 9),
        );
        scheduledId = task.id;
        for (var i = 1; i <= 3; i++) {
          await repo.createTask(
            title: 'All day $i',
            dueDate: DateTime(now.year, now.month, now.day),
          );
        }
        await repo.saveTask(
          task.copyWith(
            isAllDay: false,
            startDate: task.dueDate,
            dueDate: task.dueDate!.add(const Duration(hours: 1)),
          ),
        );
        for (final entry in [('pdf', 'report.pdf'), ('image', 'photo.png')]) {
          final path = 'files/${entry.$2}';
          final file = File('${root.path}/$path');
          await file.parent.create(recursive: true);
          if (entry.$1 == 'image') {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 320, 240),
              Paint()..color = Colors.lightBlue.shade200,
            );
            canvas.drawCircle(
              const Offset(250, 50),
              25,
              Paint()..color = Colors.amber,
            );
            canvas.drawPath(
              Path()
                ..moveTo(0, 240)
                ..lineTo(110, 85)
                ..lineTo(230, 240)
                ..close(),
              Paint()..color = Colors.teal,
            );
            canvas.drawPath(
              Path()
                ..moveTo(140, 240)
                ..lineTo(250, 130)
                ..lineTo(320, 240)
                ..close(),
              Paint()..color = Colors.green,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(320, 240);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
          } else {
            await file.writeAsBytes([37, 80, 68, 70]);
          }
          await ManagedFileRepository(db).commit(
            ImportedFile(
              id: entry.$1,
              relativePath: path,
              name: entry.$2,
              size: await file.length(),
              sha256: entry.$1,
            ),
          );
        }
        final photo = (await ManagedFileRepository(db).find('image'))!;
        thumbnail = (await ThumbnailCache(ManagedFileStorage(root.path))
            .get(photo))!;
        for (final font in {
          'Ahem': 'C:/Windows/Fonts/msyh.ttc',
          'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons': 'D:/ProgramData/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          if (await File(font.value).exists()) {
            await (FontLoader(font.key)..addFont(
                  Future.value(
                    ByteData.sublistView(await File(font.value).readAsBytes()),
                  ),
                ))
                .load();
          }
        }
      });
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dataRootPathProvider.overrideWithValue(root.path),
          attachmentOpenerProvider.overrideWithValue(opener),
        ],
      );
      final boundary = GlobalKey();
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> waitFileBatch() async {
        for (var i = 0; i < 80; i++) {
          await settle();
          if (tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('files-multi-select')),
                  )
                  .onPressed !=
              null) {
            return;
          }
        }
        fail('File operation did not finish');
      }

      Future<void> capture(String name) async {
        for (var frame = 0; frame < 5; frame++) {
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/fly204-$name-${size.width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const FlyApp()),
          ),
        );
        await settle();
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/customers/all',
        );
        expect(
          find.byKey(ValueKey('phone-customer-$customerId')),
          findsOneWidget,
        );
        expect(find.textContaining('Ctrl+K'), findsNothing);
        expect(find.text('Fly'), findsNothing);
        expect(find.byKey(const ValueKey('primary-settings')), findsNothing);
        expect(
          find.byKey(const ValueKey('mobile-sync-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('customer-search-input')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('customer-search-button')));
        await settle();
        await tester.enterText(
          find.byKey(const ValueKey('customer-search-input')),
          'Desktop customer',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settle();
        expect(
          find.byKey(ValueKey('phone-customer-$customerId')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('关闭搜索'));
        await settle();
        expect(
          find.byKey(const ValueKey('customer-search-input')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('customer-add-button')));
        await settle();
        await tester.enterText(
          find.byKey(const ValueKey('customer-quick-add-input')),
          'Phone created customer',
        );
        await tester.tap(find.byKey(const ValueKey('phone-create-customer')));
        await settle();
        expect(find.text('Phone created customer'), findsOneWidget);
        await capture('customers');
        await tester.tap(find.byKey(ValueKey('phone-customer-$customerId')));
        await settle();
        expect(
          find.byKey(const ValueKey('customer-detail-sheet')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture('customer-detail');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('customer-notes-preview')),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('customer-detail-sheet')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle();
        await tester.tap(find.byKey(const ValueKey('customer-notes-preview')));
        await settle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('workspace-sheet-close')));
        await settle();
        container.read(appRouterProvider).go('/orders/all');
        await settle();
        expect(find.byKey(const ValueKey('order-add-button')), findsOneWidget);
        expect(find.byKey(const ValueKey('order-search-input')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('order-search-button')));
        await settle();
        final orderNumber = (await tester.runAsync(
          () => DriftOrderRepository(db).watchOrder(orderId).first,
        ))!.orderNumber;
        await tester.enterText(
          find.byKey(const ValueKey('order-search-input')),
          orderNumber,
        );
        await settle();
        expect(find.byKey(ValueKey('phone-order-$orderId')), findsOneWidget);
        await tester.tap(find.byTooltip('关闭搜索'));
        await settle();
        await tester.tap(find.byKey(ValueKey('phone-order-$orderId')));
        await settle();
        expect(
          find.byKey(const ValueKey('order-detail-sheet')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture('order-detail');
        await tester.tap(find.byKey(const ValueKey('order-customer-link')));
        await settle();
        expect(
          find.byKey(const ValueKey('customer-detail-sheet')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('order-detail-sheet')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('workspace-sheet-close')));
        await settle();
        await tester.runAsync(() async {
          await precacheImage(
            ResizeImage(FileImage(thumbnail), width: 240),
            tester.element(find.byKey(const ValueKey('compact-navigation'))),
          ).timeout(const Duration(seconds: 10));
        });
        container.read(appRouterProvider).go('/files');
        await settle();
        expect(find.byKey(const ValueKey('file-view-mode')), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);
        expect(find.byKey(const ValueKey('file-search-input')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('file-search-button')));
        await settle();
        await tester.enterText(
          find.byKey(const ValueKey('file-search-input')),
          'report',
        );
        await settle();
        expect(find.text('report.pdf'), findsOneWidget);
        expect(find.text('photo.png'), findsNothing);
        await tester.tap(find.byTooltip('关闭搜索'));
        await settle();
        await tester.tap(find.byKey(const ValueKey('file-add-button')));
        await settle();
        expect(find.byKey(const ValueKey('file-take-photo')), findsOneWidget);
        Navigator.of(
          tester.element(find.byKey(const ValueKey('file-take-photo'))),
        ).pop();
        await settle();
        expect(
          tester.getTopLeft(find.text('photo.png')).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text('report.pdf')).dy),
        );
        await capture('gallery');
        await tester.tap(find.byKey(const ValueKey('files-multi-select')));
        await settle();
        await tester.tap(find.byKey(const ValueKey('file-check-image')));
        await settle();
        expect(find.text('已选 1 项'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('files-select-all')));
        await settle();
        expect(find.text('已选 2 项'), findsOneWidget);
        await capture('multi-select');
        await tester.tap(find.byKey(const ValueKey('files-batch-share')));
        await waitFileBatch();
        expect((shared!['paths'] as List).length, 2);
        expect(
          shared!['mimeTypes'],
          containsAll(['image/png', 'application/pdf']),
        );
        for (
          var i = 0;
          i < 40 &&
              tester
                      .widget<IconButton>(
                        find.byKey(const ValueKey('files-multi-select')),
                      )
                      .onPressed ==
                  null;
          i++
        ) {
          await settle();
        }
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('files-multi-select')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('files-multi-select')));
        await settle();
        expect(find.byKey(const ValueKey('files-selection-bar')), findsNothing);

        expect(find.byType(Image), findsOneWidget);
        expect(
          tester.widget<RawImage>(find.byType(RawImage).first).image,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('file-kind-order')));
        await settle();
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<bool>, '文件在前'),
        );
        await settle();
        expect(
          tester.getTopLeft(find.text('report.pdf')).dx,
          lessThan(tester.getTopLeft(find.text('photo.png')).dx),
        );
        await capture('gallery-files-first');
        await tester.ensureVisible(find.text('photo.png'));
        await tester.longPress(find.text('photo.png'));
        await settle();
        for (final action in ['详情', '重命名', '分享', '删除']) {
          expect(find.text(action), findsOneWidget);
        }
        await capture('file-actions');
        shareResult = 'dev.fluttercommunity.plus/share/unavailable';
        await tester.tap(find.text('分享'));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await waitFileBatch();
        expect(shared!['paths'], [endsWith('photo.png')]);
        expect(shared!['mimeTypes'], ['image/png']);
        expect(
          await tester.runAsync(
            () => File((shared!['paths'] as List).single as String).exists(),
          ),
          isTrue,
          reason: 'Platforms without completion callbacks retain files for the receiver',
        );
        await tester.tap(find.byKey(const ValueKey('file-view-mode')));
        await settle();
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<FileViewMode>, '列表'),
        );
        await settle();
        expect(
          tester
              .widget<FileEntryContent>(find.byType(FileEntryContent).first)
              .mode,
          FileViewMode.list,
        );
        await capture('files');
        await tester.ensureVisible(find.text('report.pdf'));
        await settle();
        await tester.tap(find.text('report.pdf'));
        await settle();
        expect(opener.paths.single, endsWith('report.pdf'));
        expect(find.byKey(const ValueKey('file-preview-pdf')), findsNothing);
        await tester.ensureVisible(find.text('photo.png'));
        await settle();
        await tester.tap(find.text('photo.png'));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await settle();
        expect(find.byKey(const ValueKey('image-file-viewer')), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close).last);
        await settle();
        container.read(appRouterProvider).go('/calendar');
        await settle();
        expect(find.text('Scheduled task'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-all-day-toggle')),
          findsOneWidget,
        );
        expect(find.text('All day 2'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('calendar-all-day-toggle')));
        await settle();
        expect(find.text('All day 2'), findsOneWidget);
        await capture('all-day-expanded');
        await tester.tap(find.byKey(const ValueKey('calendar-all-day-toggle')));
        await settle();
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day);
        final event = find.byKey(
          ValueKey('week-drag-$scheduledId-${now.weekday - 1}'),
        );
        await Scrollable.ensureVisible(tester.element(event), alignment: .4);
        await settle();
        final source = tester.getCenter(event);
        final slot = find.byKey(
          ValueKey('week-drop-${day.toIso8601String()}-555'),
        );
        final gesture = await tester.startGesture(source);
        await tester.pump(const Duration(milliseconds: 650));
        expect(
          find.text('Scheduled task'),
          findsNWidgets(2),
          reason: 'drag feedback appears after long press',
        );
        await gesture.moveTo(tester.getCenter(slot));
        await tester.pump(const Duration(milliseconds: 80));
        await capture('calendar-dragging');
        await gesture.up();
        await settle();
        final changed = (await tester.runAsync(
          () => DriftTaskRepository(db).watchTask(scheduledId).first,
        ))!;
        expect(
          changed.startDate,
          DateTime(now.year, now.month, now.day, 9, 15),
        );
        expect(changed.dueDate, DateTime(now.year, now.month, now.day, 10, 15));
        expect(find.textContaining('已改期至'), findsOneWidget);
        await tester.tap(find.text('撤销'));
        await settle();
        for (final mode in ['周', '月']) {
          await tester.tap(find.byKey(const ValueKey('mobile-calendar-view')));
          await settle();
          expect(
            find.byType(CheckedPopupMenuItem<MobileCalendarView>),
            findsNWidgets(2),
          );
          await tester.tap(
            find.widgetWithText(CheckedPopupMenuItem<MobileCalendarView>, mode),
          );
          await settle();
          expect(tester.takeException(), isNull, reason: mode);
          await capture('calendar-$mode');
        }
        final monthEvent = find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key as ValueKey<String>).value.startsWith(
                    'month-drag-',
                  ),
            )
            .first;
        final monthDrag = tester
            .widget<LongPressDraggable<CalendarTaskDrag>>(
              find
                  .ancestor(
                    of: monthEvent,
                    matching: find.byType(LongPressDraggable<CalendarTaskDrag>),
                  )
                  .first,
            )
            .data!;
        final tomorrow = DateTime(day.year, day.month, day.day + 1);
        final monthTarget = find.byKey(
          ValueKey('month-drop-${tomorrow.toIso8601String()}'),
        );
        await Scrollable.ensureVisible(
          tester.element(monthEvent),
          alignment: .4,
        );
        await settle();
        final monthGesture = await tester.startGesture(
          tester.getCenter(monthEvent),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await monthGesture.moveTo(tester.getCenter(monthTarget));
        await tester.pump(const Duration(milliseconds: 60));
        await monthGesture.up();
        await settle();
        final monthMoved = (await tester.runAsync(
          () => DriftTaskRepository(db).watchTask(monthDrag.task.id).first,
        ))!;
        expect(
          monthMoved.dueDate,
          shiftCalendarTask(monthDrag.task, day, tomorrow).dueDate,
        );
        expect(monthMoved.isAllDay, monthDrag.task.isAllDay);
        await capture('calendar-month-moved');
        await tester.tap(find.text('撤销'));
        await settle();
        await tester.tap(find.byKey(const ValueKey('mobile-calendar-create')));
        await settle();
        await tester.enterText(
          find.byKey(const ValueKey('mobile-calendar-title')),
          'New calendar task',
        );
        await tester.tap(find.byKey(const ValueKey('mobile-calendar-save')));
        await settle();
        expect(find.text('New calendar task'), findsOneWidget);
        container.read(appRouterProvider).go('/tasks/today');
        await settle();
        expect(find.byKey(const ValueKey('task-view-review')), findsOneWidget);
        await capture('tasks');
        await tester.tap(find.byType(Checkbox).first);
        await settle();
        expect(find.text('任务已完成'), findsOneWidget);
        await tester.tap(find.text('撤销'));
        await settle();
        await tester.tap(find.byKey(const ValueKey('task-view-lists')));
        await settle();
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('mobile-list-$childListId')),
          130,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('mobile-inline-list-filters')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle();
        expect(find.text('Work project'), findsWidgets);
        await capture('task-lists');
        await tester.tap(find.text('Deliveries'));
        await settle();
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/tasks/list/$childListId',
        );
        expect(find.text('Nested list task'), findsOneWidget);
        expect(find.text('Work project / Deliveries'), findsOneWidget);
        expect(find.byKey(const ValueKey('quick-add-input')), findsNothing);
        final viewKeys = ['tasks', 'lists', 'review', 'calendar', 'matrix'];
        for (var index = 1; index < viewKeys.length; index++) {
          expect(
            tester
                .getTopLeft(
                  find.byKey(ValueKey('task-view-${viewKeys[index]}')),
                )
                .dx,
            greaterThan(
              tester
                  .getTopLeft(
                    find.byKey(ValueKey('task-view-${viewKeys[index - 1]}')),
                  )
                  .dx,
            ),
          );
        }
        await tester.tap(find.byKey(const ValueKey('task-add-button')));
        await settle();
        await tester.enterText(
          find.byKey(const ValueKey('phone-task-title')),
          'Phone task in selected list',
        );
        await tester.tap(find.byKey(const ValueKey('phone-create-task')));
        await settle();
        final createdTask = (await tester.runAsync(
          () => DriftTaskRepository(db).watchAllTasks().first,
        ))!.singleWhere((task) => task.title == 'Phone task in selected list');
        expect(createdTask.listId, childListId);
        await tester.tap(find.byKey(const ValueKey('task-search-button')));
        await settle();
        await tester.enterText(
          find.byKey(const ValueKey('task-search-input')),
          'Search must not create',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settle();
        expect(find.byKey(const ValueKey('phone-task-title')), findsNothing);
        expect(
          (await tester.runAsync(
            () => DriftTaskRepository(db).watchAllTasks().first,
          ))!.where((task) => task.title == 'Search must not create'),
          isEmpty,
        );
        await tester.tap(find.byTooltip('关闭搜索'));
        await settle();
        await capture('tasks-inline-actions');
        container.read(appRouterProvider).go('/files');
        await settle();
        expect(find.byType(GridView), findsNothing);
        expect(
          tester
              .widget<FileEntryContent>(find.byType(FileEntryContent).first)
              .mode,
          FileViewMode.list,
        );
        expect(
          tester.getTopLeft(find.text('report.pdf')).dy,
          lessThan(tester.getTopLeft(find.text('photo.png')).dy),
        );
        await tester.tap(find.byKey(const ValueKey('files-multi-select')));
        await settle();
        await tester.tap(find.byKey(const ValueKey('files-select-all')));
        await settle();
        await tester.tap(find.byKey(const ValueKey('files-batch-delete')));
        await settle();
        expect(find.text('删除 2 项？'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('files-confirm-batch-delete')),
        );
        await waitFileBatch();
        expect(find.text('photo.png'), findsNothing);
        expect(find.text('report.pdf'), findsNothing);
        expect(find.text('已删除 2 项'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('mobile-sync-details')));
        await settle();
        expect(
          find.byKey(const ValueKey('sync-status-details')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sync-pending-downloads')),
          findsOneWidget,
        );
        await capture('sync-status');
        await tester.tapAt(const Offset(5, 5));
        await settle();

        container.read(appRouterProvider).go('/me');
        await settle();
        expect(find.byKey(const ValueKey('my-page')), findsOneWidget);
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(find.widgetWithText(NavigationDestination, '更多'), findsNothing);
        expect(find.text('工具'), findsNothing);
        expect(find.text('资料库'), findsNothing);
        await capture('my');
        await tester.tap(find.byKey(const ValueKey('my-account')));
        await settle();
        expect(find.byKey(const ValueKey('sync-email')), findsOneWidget);
        expect(find.byKey(const ValueKey('sync-mode-cloud')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await settle();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await db.close();
          for (var attempt = 0; ; attempt++) {
            try {
              await root.delete(recursive: true);
              break;
            } on FileSystemException {
              if (attempt >= 9) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
          }
        });
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
