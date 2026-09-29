import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

enum FileCollection { recent, folder, customers, deleted }

enum FileSort { modified, created, name, type, size }

class FileBrowserEntry {
  const FileBrowserEntry(
    this.file,
    this.customerName,
    this.companyName,
    this.fileTags,
    this.customerTags, {
    this.orderNumber = '',
    this.customerId,
    this.orderId,
  });
  final AttachmentRecord file;
  final String customerName, companyName, fileTags, customerTags;
  final String orderNumber;
  final String? customerId, orderId;
  String get name =>
      file.displayName.isEmpty ? file.originalName : file.displayName;
}

class FileBrowserQuery {
  FileBrowserQuery(this.db);
  final AppDatabase db;
  Stream<List<FileBrowserEntry>> watch({
    required FileCollection collection,
    String? folderId,
    bool descendants = false,
    String search = '',
    Set<String> fileTags = const {},
    Set<String> customerTags = const {},
    FileSort sort = FileSort.modified,
    bool crmVisible = true,
    String? fileId,
  }) {
    final vars = <Variable>[];
    final where = <String>[];
    if (fileId != null) {
      where.add('a.id=?');
      vars.add(Variable(fileId));
    }
    if (collection == FileCollection.deleted) {
      where.add("a.deleted_at IS NOT NULL AND a.owner_type='library'");
    } else {
      where.add('a.deleted_at IS NULL');
    }
    if (!crmVisible) {
      where.add("a.owner_type NOT IN ('customer','order','cost','payment')");
    }
    switch (collection) {
      case FileCollection.customers:
        where.add(
          "a.owner_type IN ('customer','order','payment','cost') AND c.deleted_at IS NULL AND c.id IS NOT NULL",
        );
      case FileCollection.folder:
        where.add("a.owner_type='library'");
        if (folderId == null) {
          if (!descendants) where.add('a.folder_id IS NULL');
        } else if (descendants) {
          where.add(
            'a.folder_id IN (WITH RECURSIVE tree(id) AS (SELECT ? UNION SELECT f.id FROM file_folders f JOIN tree ON f.parent_id=tree.id WHERE f.deleted_at IS NULL) SELECT id FROM tree)',
          );
          vars.add(Variable(folderId));
        } else {
          where.add('a.folder_id=?');
          vars.add(Variable(folderId));
        }
      case FileCollection.recent:
      case FileCollection.deleted:
        break;
    }
    for (final id in fileTags) {
      where.add(
        'EXISTS (SELECT 1 FROM file_tag_links ft WHERE ft.file_id=a.id AND ft.tag_id=?)',
      );
      vars.add(Variable(id));
    }
    for (final id in customerTags) {
      where.add(
        'EXISTS (SELECT 1 FROM customer_tag_links ct JOIN tags t ON t.id=ct.tag_id WHERE ct.customer_id=c.id AND t.deleted_at IS NULL AND t.is_active=1 AND ct.tag_id=?)',
      );
      vars.add(Variable(id));
    }
    if (search.trim().isNotEmpty) {
      where.add(
        "instr(lower(a.display_name || ' ' || a.original_name || ' ' || a.file_name || ' ' || coalesce(o.order_number,'') || ' ' || coalesce(c.name,'') || ' ' || coalesce(c.company_name,'') || ' ' || coalesce((SELECT group_concat(t.name,' ') FROM file_tag_links l JOIN file_tags t ON t.id=l.tag_id WHERE l.file_id=a.id),'') || ' ' || coalesce((SELECT group_concat(t.name,' ') FROM customer_tag_links l JOIN tags t ON t.id=l.tag_id WHERE l.customer_id=c.id AND t.deleted_at IS NULL AND t.is_active=1),'')),?)>0",
      );
      vars.add(Variable(search.trim().toLowerCase()));
    }
    final order = switch (sort) {
      FileSort.modified => 'a.updated_at DESC',
      FileSort.created => 'a.created_at DESC',
      FileSort.name =>
        "coalesce(nullif(a.display_name,''),a.original_name) COLLATE NOCASE",
      FileSort.type => 'a.mime_type',
      FileSort.size => 'a.file_size DESC',
    };
    return db
        .customSelect(
          '''SELECT a.*, coalesce(c.name,'') AS customer_name, coalesce(c.company_name,'') AS company_name,
      coalesce(o.order_number,'') AS order_number, c.id AS related_customer_id, o.id AS related_order_id,
      coalesce((SELECT group_concat(t.name,' · ') FROM file_tag_links l JOIN file_tags t ON t.id=l.tag_id WHERE l.file_id=a.id),'') AS file_tag_names,
      coalesce((SELECT group_concat(t.name,' · ') FROM customer_tag_links l JOIN tags t ON t.id=l.tag_id WHERE l.customer_id=c.id AND t.deleted_at IS NULL AND t.is_active=1),'') AS customer_tag_names
      FROM attachments a
      LEFT JOIN order_payments p ON a.owner_type='payment' AND a.owner_id=p.id AND p.deleted_at IS NULL
      LEFT JOIN order_cost_entries e ON a.owner_type='cost' AND a.owner_id=e.id AND e.deleted_at IS NULL
      LEFT JOIN orders o ON o.id=CASE a.owner_type
        WHEN 'order' THEN a.owner_id WHEN 'payment' THEN p.order_id WHEN 'cost' THEN e.order_id END
        AND o.deleted_at IS NULL
      LEFT JOIN customers c ON c.id=CASE WHEN a.owner_type='customer' THEN a.owner_id ELSE o.customer_id END
        AND c.deleted_at IS NULL
      WHERE ${where.join(' AND ')} ORDER BY $order,a.id ${collection == FileCollection.recent ? 'LIMIT 100' : ''}''',
          variables: vars,
          readsFrom: {
            db.attachments,
            db.customers,
            db.orders,
            db.orderPayments,
            db.orderCostEntries,
            db.fileTags,
            db.fileTagLinks,
            db.customerTagLinks,
            db.tags,
            db.fileFolders,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => FileBrowserEntry(
                  db.attachments.map(r.data),
                  r.read('customer_name'),
                  r.read('company_name'),
                  r.read('file_tag_names'),
                  r.read('customer_tag_names'),
                  orderNumber: r.read('order_number'),
                  customerId: r.readNullable<String>('related_customer_id'),
                  orderId: r.readNullable<String>('related_order_id'),
                ),
              )
              .toList(),
        );
  }
}
