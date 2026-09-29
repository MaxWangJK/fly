import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tools/container_loading/presentation/container_loading_providers.dart';
import 'package:fly/features/tools/container_loading/domain/models/container_loading_models.dart';
import 'package:fly/features/tools/container_loading/domain/models/section_models.dart';
import 'package:fly/shared/dev/first_run_demo_seeder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sales materials render real UI with isolated demo data', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('FLY_SALES_CAPTURE')) return;
    await tester.runAsync(() async {
      for (final pair in [
        ('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc'),
        // Some controls fall back to the test-only Ahem font. Supply the
        // production Chinese font there too instead of square test glyphs.
        ('Ahem', r'C:\Windows\Fonts\msyh.ttc'),
        ('Segoe UI', r'C:\Windows\Fonts\segoeui.ttf'),
        ('Segoe UI Emoji', r'C:\Windows\Fonts\seguiemj.ttf'),
        (
          'MaterialIcons',
          r'D:\ProgramData\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
        ),
      ]) {
        final loader = FontLoader(pair.$1)
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(pair.$2).readAsBytes()),
            ),
          );
        await loader.load();
      }
    });
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      await db.ensureBuiltInData();
      await FirstRunDemoSeeder(
        database: db,
        tasks: DriftTaskRepository(db),
        customers: DriftCustomerRepository(db),
        orders: DriftOrderRepository(db),
      ).seedIfEligible();
    });
    final providers = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(providers.dispose);
    final raw = GlobalKey(), poster = GlobalKey();
    final copy = ValueNotifier((
      '把外贸日常\n放进一个工作台',
      '客户跟进、订单执行、任务安排与装柜规划',
      'Windows 桌面版  /  本地数据',
    ));
    addTearDown(copy.dispose);
    final app = UncontrolledProviderScope(
      container: providers,
      child: RepaintBoundary(key: raw, child: const FlyApp()),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'Microsoft YaHei UI',
            color: Color(0xFF252B29),
          ),
          child: ValueListenableBuilder(
            valueListenable: copy,
            builder: (context, text, _) => RepaintBoundary(
              key: poster,
              child: Container(
                color: const Color(0xFFF1E8DB),
                padding: const EdgeInsets.fromLTRB(60, 40, 60, 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'Fly',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '外贸工作台',
                          style: TextStyle(
                            fontSize: 22,
                            color: Color(0xFF687B61),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      text.$1,
                      style: const TextStyle(
                        fontSize: 60,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      text.$2,
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1.5,
                        color: Color(0xFF596158),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFD6CBBB)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 1280,
                          height: 750,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: 1400,
                              height: 820,
                              child: app,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      text.$3,
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF60794F),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '真实软件界面 · 演示数据非真实业务记录',
                      style: TextStyle(fontSize: 18, color: Color(0xFF72786F)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> shoot(
      String name,
      String title,
      String description,
      String points,
    ) async {
      copy.value = (title, description, points);
      await settle();
      await tester.runAsync(() async {
        for (final pair in [(poster, '商品图片'), (raw, '原始截图')]) {
          final boundary =
              pair.$1.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File('docs/marketing/fly-sales-v1/${pair.$2}/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        }
      });
    }

    Future<void> module(String name) async {
      await tester.tap(find.byKey(ValueKey('primary-$name')));
      await settle();
    }

    await settle();
    await module('dashboard');
    await shoot(
      '01_主图',
      '把外贸日常\n放进一个工作台',
      '客户 · 订单 · 任务 · 日历 · 四象限 · 装柜模拟',
      'Windows 桌面版  /  本地数据  /  简洁操作',
    );
    await module('customers');
    await tester.tap(find.text('Jack Lim'));
    await settle();
    await shoot(
      '02_客户跟进',
      '今天该联系谁？\n打开就有方向',
      '把客户资料、跟进记录和下一步安排放在一起',
      '客户分级与标签  /  重复跟进  /  关联订单',
    );
    await module('orders');
    await tester.tap(find.text('SO-${DateTime.now().year}-001'));
    await settle();
    await shoot(
      '03_订单执行',
      '订单走到哪一步\n不必到处翻记录',
      '把客户、工厂、产品与执行状态集中查看',
      '工厂下单状态  /  文件归档  /  客户双向跳转',
    );
    await tester.tap(find.byKey(const ValueKey('order-financial-preview')));
    await settle();
    await tester.drag(find.text('成本与费用'), const Offset(0, -380));
    await settle();
    expect(find.text('利润率'), findsOneWidget);
    await settle();
    await shoot(
      '04_收款利润',
      '还有多少没收？\n预计利润是多少？',
      '逐笔记录收款，汇总费用与预计利润',
      '应收与未收  /  成本与退税  /  预计利润',
    );
    // Close the extension panel before changing workspace.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    await module('tasks');
    await tester.tap(find.text('确认菲律宾客户首柜数量'));
    await settle();
    await shoot(
      '05_任务安排',
      '要做的事情\n有条理地推进',
      '用清单、日期和优先级，安排每一天的工作',
      '今天与最近7天  /  标签分类  /  任务详情',
    );
    await module('calendar');
    await shoot(
      '06_日历视图',
      '把工作安排\n放到日期上',
      '在月历中查看任务，按日期快速添加',
      '月历总览  /  日期添加任务  /  轻量编辑',
    );
    await module('matrix');
    await shoot(
      '07_四象限',
      '重要与紧急\n分开看更清楚',
      '按重要性和紧急性整理任务，辅助取舍',
      '重要且紧急  /  重要不紧急  /  四象限分类',
    );
    await module('tools');
    final editor = providers.read(loadingEditorProvider);
    final cargo = providers.read(cargoLibraryProvider).requireValue;
    final wpc = cargo.firstWhere((c) => c.id == 'cargo-wpc-grille');
    for (final section in editor.sections.skip(1)) {
      editor.addCargo(section.id, wpc);
    }
    final firstSection = editor.sections.first.id;
    const pallet = CargoPackageModel(
      id: 'sales-pallet',
      name: '标准托盘',
      type: CargoPackageType.pallet,
      dimensions: Dimensions3(2800, 1200, 800),
      weightGrams: 800000,
      colorValue: 0xFFB18CAF,
    );
    const pvc = CargoPackageModel(
      id: 'sales-pvc',
      name: 'PVC ceiling',
      dimensions: Dimensions3(2900, 250, 100),
      weightGrams: 3000,
      colorValue: 0xFFD3A06D,
    );
    editor.addCargo(firstSection, pallet);
    editor.updateEntry(
      editor.entries.last.copyWith(
        quantity: 1,
        horizontalPlacement: HorizontalPlacement.left,
      ),
    );
    final spaces = editor.spacesFor(firstSection);
    editor.addCargo(firstSection, pvc, spaceId: spaces[0].id);
    editor.addCargo(firstSection, wpc, spaceId: spaces[1].id);
    editor.scene.focusSection(null);
    await shoot(
      '08_装柜规划',
      '装柜方案\n先看清，再安排',
      '按分节配置货物与数量，实时查看 3D 摆放',
      '托盘与纸箱  /  剩余空间  /  保存方案\n规划仅供参考，实际装载需核实尺寸、承重与支撑',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
