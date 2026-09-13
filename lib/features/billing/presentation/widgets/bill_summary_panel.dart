import 'package:flutter/material.dart';

import '../../../../core/money/money_display.dart';
import '../../domain/models/bill_totals.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/cart_line.dart';

/// Read-only statement of what is being charged: the lines, then the money.
///
/// Used on every step of checkout and on the settled bill, so the figures the cashier
/// confirms are rendered by the same code that shows them afterwards. Every amount is
/// read from the cart and the totals; nothing is summed here.
class BillSummaryPanel extends StatelessWidget {
  const BillSummaryPanel({
    required this.cart,
    required this.totals,
    this.title = 'Bill',
    super.key,
  });

  /// Fits the longest item name with a size, a quantity and a line total.
  static const double width = 372;

  final Cart cart;

  final BillTotals totals;

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleMedium),
              Text(
                '${cart.lineCount} '
                '${cart.lineCount == 1 ? 'line' : 'lines'} \u00b7 '
                '${cart.itemCount} '
                '${cart.itemCount == 1 ? 'item' : 'items'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: cart.lineCount,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) =>
                _SummaryLine(line: cart.lines[index]),
          ),
        ),
        const Divider(height: 1),
        _TotalsBlock(totals: totals),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? optionsSummary = line.optionsSummary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 32,
                child: Text(
                  '${line.quantity}\u00d7',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  line.displayName,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(line.lineTotal.formatted, style: theme.textTheme.bodyMedium),
            ],
          ),
          if (optionsSummary != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Text(
                optionsSummary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({required this.totals});

  final BillTotals totals;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _AmountRow(
            label: 'Subtotal',
            amount: totals.subtotal.formatted,
            style: theme.textTheme.bodyMedium,
          ),
          // Shown only when there is something to show. A row of zeroes would imply
          // a discount scheme and a tax rate that this build does not have.
          if (totals.hasAdjustments) ...<Widget>[
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Discount',
              amount: '-${totals.discount.formatted}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Tax',
              amount: totals.tax.formatted,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text('Total', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                totals.total.formatted,
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
          if (!totals.hasAdjustments) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'No discount or tax is applied. Neither is configured yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    required this.style,
  });

  final String label;

  final String amount;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Text(
          label,
          style: style?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(amount, style: style),
      ],
    );
  }
}
