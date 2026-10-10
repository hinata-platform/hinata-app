import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/soft_card.dart';
import 'billing_format.dart';

/// The pieces an invoice is shown with, in the list and on its own page.

/// Where a record stands, in words with a glyph — never colour alone.
class InvoiceStatusLabel extends StatelessWidget {
  const InvoiceStatusLabel({super.key, required this.invoice});

  final InvoiceSummary invoice;

  @override
  Widget build(BuildContext context) {
    final (icon, color, key) = invoice.isDraft
        ? (
            LucideIcons.filePen,
            AppColors.accentInk,
            'billing.invoice.status.draft',
          )
        : invoice.isCredited
        ? (
            LucideIcons.fileX2,
            AppColors.inkSoft,
            'billing.invoice.status.credited',
          )
        : invoice.kind == InvoiceKind.creditNote
        ? (
            LucideIcons.fileMinus2,
            AppColors.inkSoft,
            'billing.invoice.status.creditNote',
          )
        : (
            LucideIcons.fileCheck2,
            AppColors.successInk,
            'billing.invoice.status.issued',
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            context.t(key),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// What a record is called: its number, or "draft".
String invoiceTitle(BuildContext context, InvoiceSummary invoice) {
  final number = invoice.number;
  if (number == null) return context.t('billing.invoice.draftTitle');
  return context.t(
    invoice.kind == InvoiceKind.creditNote
        ? 'billing.invoice.creditNoteNumber'
        : 'billing.invoice.number',
    variables: {'number': number},
  );
}

/// The service period, localized.
String invoicePeriod(BuildContext context, InvoiceSummary invoice) {
  final from = invoice.periodFrom;
  final to = invoice.periodTo;
  if (from == null || to == null) return '';
  final format = DateFormat.yMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  return '${format.format(from)} – ${format.format(to)}';
}

/// The project as the reader may name it: key and name, or the key alone.
String invoiceProject(InvoiceSummary invoice) =>
    [?invoice.projectKey, ?invoice.projectName].join(' · ');

/// One record in the list.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.invoice, required this.onTap});

  final InvoiceSummary invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = [
      invoiceProject(invoice),
      invoicePeriod(context, invoice),
      ?invoice.recipientName,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Semantics(
      button: true,
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoiceTitle(context, invoice),
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        secondary,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InvoiceStatusLabel(invoice: invoice),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatMoney(
                    context,
                    invoice.totals.grossCents,
                    invoice.currency,
                  ),
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
