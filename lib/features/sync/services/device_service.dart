import '../domain/sync_protocol.dart';

class DeviceService {
  DeviceService(this.transport);
  final SyncTransport transport;
  Future<List<Map<String, dynamic>>> list() async =>
      ((await transport.request('GET', '/devices'))['items'] as List)
          .map((d) => (d as Map).cast<String, dynamic>())
          .toList();
  Future<void> revoke(String id) async {
    await transport.request('POST', '/devices/$id/revoke');
  }
}
