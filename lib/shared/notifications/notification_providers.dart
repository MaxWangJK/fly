import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/presentation/task_providers.dart';
import 'notification_service.dart';

final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => WindowsNotificationGateway(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(
    ref.watch(databaseProvider),
    ref.watch(notificationGatewayProvider),
  ),
);
