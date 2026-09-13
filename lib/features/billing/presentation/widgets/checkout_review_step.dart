import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../customers/domain/models/customer.dart';
import '../../../customers/domain/models/customer_phone.dart';
import '../../../orders/domain/models/order_type.dart';
import '../controllers/checkout_controller.dart';

/// First step: confirm how the order reaches the customer, and who they are.
///
/// The lines and the money are on the bill summary beside this step, so nothing is
/// repeated here. What this step collects is the two things the cart cannot know.
class CheckoutReviewStep extends StatelessWidget {
  const CheckoutReviewStep({super.key});

  @override
  Widget build(BuildContext context) {
    final CheckoutController controller = context.watch<CheckoutController>();
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: <Widget>[
        Text('Order type', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        const _OrderTypeChoices(),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Text('Customer', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            Text(
              controller.requiresCustomerPhone ? 'Required' : 'Optional',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _CustomerPhoneField(),
        const SizedBox(height: 24),
        Text('Note on the bill', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        const _NotesField(),
      ],
    );
  }
}

class _OrderTypeChoices extends StatelessWidget {
  const _OrderTypeChoices();

  @override
  Widget build(BuildContext context) {
    final CheckoutController controller = context.watch<CheckoutController>();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final OrderType type in OrderType.values)
          ChoiceChip(
            label: Text(type.label),
            selected: controller.orderType == type,
            onSelected: (bool _) =>
                context.read<CheckoutController>().selectOrderType(type),
          ),
      ],
    );
  }
}

/// Phone entry, which is how the counter identifies a returning customer.
///
/// The controller keeps the digits of whatever is typed and decides whether they amount
/// to a usable number. It does not shorten anything to fit, so a number that cannot be
/// stored is reported here rather than quietly turned into a different one.
class _CustomerPhoneField extends StatefulWidget {
  const _CustomerPhoneField();

  @override
  State<_CustomerPhoneField> createState() => _CustomerPhoneFieldState();
}

class _CustomerPhoneFieldState extends State<_CustomerPhoneField> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(
      text: context.read<CheckoutController>().customerPhone,
    );
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CheckoutController controller = context.watch<CheckoutController>();

    // The controller is the source of truth: it strips anything that is not a digit,
    // so the field is corrected back to what was actually accepted.
    if (_field.text != controller.customerPhone) {
      _field.value = TextEditingValue(
        text: controller.customerPhone,
        selection: TextSelection.collapsed(
          offset: controller.customerPhone.length,
        ),
      );
    }

    // Only reported once something has been entered. An empty field on a takeaway is
    // not a mistake, it is a walk-in.
    final String? problem = controller.hasCustomerPhone
        ? controller.customerPhoneProblem
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _field,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Phone number',
            hintText: '${CustomerPhone.digits} digits',
            prefixIcon: const Icon(Icons.phone_outlined),
            errorText: problem,
            helperText: controller.requiresCustomerPhone
                ? 'Needed because this order leaves the outlet.'
                : 'Leave empty for a walk-in.',
          ),
          onChanged: context.read<CheckoutController>().setCustomerPhone,
        ),
        if (controller.isReturningCustomer) ...<Widget>[
          const SizedBox(height: 8),
          _ReturningCustomerNote(customer: controller.knownCustomer!),
        ],
      ],
    );
  }
}

/// Says that this number is already on file.
///
/// A hint, not a gate. It is here because knowing the person at the counter has been
/// before is worth a glance, and because it tells the cashier the number they typed is
/// the one they meant. Nothing about the sale depends on it.
class _ReturningCustomerNote extends StatelessWidget {
  const _ReturningCustomerNote({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? name = customer.name?.trim();

    return Row(
      children: <Widget>[
        Icon(
          Icons.how_to_reg_outlined,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name == null || name.isEmpty
                ? 'Returning customer'
                : 'Returning customer: $name',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotesField extends StatefulWidget {
  const _NotesField();

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(
      text: context.read<CheckoutController>().notes,
    );
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _field,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Note',
        hintText: 'Anything that should appear on the bill',
      ),
      onChanged: context.read<CheckoutController>().setNotes,
    );
  }
}
