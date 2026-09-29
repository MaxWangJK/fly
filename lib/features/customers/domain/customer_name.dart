import 'customer.dart';

String normalizeCustomerName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class DuplicateCustomerName implements Exception {
  DuplicateCustomerName(this.existing);
  final Customer existing;
}
