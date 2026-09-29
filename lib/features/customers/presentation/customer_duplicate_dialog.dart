import 'package:flutter/material.dart';

import '../../../l10n/fly_localizations.dart';
import '../domain/customer.dart';

Future<bool> showCustomerDuplicate(
  BuildContext context,
  Customer customer,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          context.l10n
              .t('customerNameExists')
              .replaceAll('{name}', customer.name),
        ),
        content: Text(
          [
            customer.companyName,
            customer.country,
          ].where((s) => s.isNotEmpty).join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.t('useDifferentName')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.l10n.t('openExistingCustomer')),
          ),
        ],
      ),
    ) ??
    false;
