import 'dart:developer' as developer;

import '../domain/financial_attachment_ids.dart';
import '../domain/order.dart';
import '../domain/order_repository.dart';
import 'order_file_service.dart';

/// Import first, then save the entire attachment selection with the entry.
/// Removing a reference leaves the original in the order's files (it may be
/// used by another entry). Cancelling the dialog performs no file operations.
class FinancialAttachmentService {
  const FinancialAttachmentService(this.repository, this.storage);
  final OrderRepository repository;
  final OrderFileStorage storage;

  Future<void> save({
    required String orderId,
    required OrderDocumentType documentType,
    required List<String> retainedIds,
    required List<String> sourcePaths,
    required Future<void> Function(String? attachmentId) persist,
  }) async {
    final imported = <OrderFile>[];
    final storedPaths = <String>[];
    try {
      for (final path in sourcePaths) {
        final file = await storage.importFile(
          sourcePath: path,
          orderId: orderId,
          documentType: documentType,
        );
        storedPaths.add(file.relativePath);
        imported.add(
          await repository.addFileMetadata(
            orderId: orderId,
            fileName: file.fileName,
            originalName: file.originalName,
            documentType: documentType,
            localRelativePath: file.relativePath,
            fileSize: file.fileSize,
            mimeType: file.mimeType,
          ),
        );
      }
      await persist(
        FinancialAttachmentIds.encode([
          ...retainedIds,
          ...imported.map((file) => file.id),
        ]),
      );
    } catch (error, stack) {
      // Try every cleanup even if one file is already missing. Preserve the
      // original error so the form can explain the failed save and be retried.
      for (final file in imported) {
        try {
          await repository.removeFile(file.id);
        } catch (cleanupError, cleanupStack) {
          developer.log(
            "Unable to clean up a failed financial attachment import",
            name: "fly.orders.attachments",
            error: cleanupError,
            stackTrace: cleanupStack,
          );
        }
      }
      for (final path in storedPaths) {
        try {
          await storage.removeStoredFile(path);
        } catch (cleanupError, cleanupStack) {
          developer.log(
            "Unable to clean up a failed financial attachment import",
            name: "fly.orders.attachments",
            error: cleanupError,
            stackTrace: cleanupStack,
          );
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}
