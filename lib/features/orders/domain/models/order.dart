import '../../../../core/data/local/sqlite/row.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/data/sync/syncable_entity.dart';
import '../../../../core/money/money.dart';
import 'order_status.dart';
import 'order_type.dart';

/// The header of a bill.
///
/// The monetary fields are stored, not derived. They are computed once when the
/// bill is settled and then persisted, so a reprint or a report reproduces the
/// original document exactly even if tax rates or menu prices change afterwards.
/// Nothing recalculates a historical total from the menu tables.
///
/// There is no table or seat reference. The outlet serves dine-in customers but
/// does not run digital table management, so there is nothing to point at.
class Order implements SyncableEntity {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.orderType,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.createdAt,
    required this.updatedAt,
    this.customerId,
    this.notes,
    this.isDeleted = false,
    this.syncState = SyncState.pending,
  });

  factory Order.fromRow(Map<String, Object?> row) {
    return Order(
      id: row.requireString(SyncColumns.id),
      orderNumber: row.requireString('orderNumber'),
      orderType: row.requireEnum<OrderType>(
        'orderType',
        OrderType.values,
        fallback: OrderType.takeaway,
      ),
      status: row.requireEnum<OrderStatus>(
        'status',
        OrderStatus.values,
        fallback: OrderStatus.draft,
      ),
      customerId: row.optionalString('customerId'),
      subtotal: Money.fromPaise(row.requireInt('subtotalPaise')),
      discountAmount: Money.fromPaise(row.requireInt('discountAmountPaise')),
      taxAmount: Money.fromPaise(row.requireInt('taxAmountPaise')),
      totalAmount: Money.fromPaise(row.requireInt('totalAmountPaise')),
      notes: row.optionalString('notes'),
      createdAt: row.requireDateTime(SyncColumns.createdAt),
      updatedAt: row.requireDateTime(SyncColumns.updatedAt),
      isDeleted: row.requireBool(SyncColumns.isDeleted),
      syncState: row.requireSyncState(SyncColumns.syncState),
    );
  }

  @override
  final String id;

  /// Human-readable number printed on the bill. Unique on this terminal.
  final String orderNumber;

  final OrderType orderType;

  final OrderStatus status;

  /// `null` for a walk-in who did not give a phone number.
  final String? customerId;

  /// Sum of line totals before bill-level discount and tax.
  final Money subtotal;

  final Money discountAmount;

  final Money taxAmount;

  /// Amount payable. Persisted as calculated at settlement time.
  final Money totalAmount;

  final String? notes;

  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final bool isDeleted;

  @override
  final SyncState syncState;

  Order copyWith({
    String? orderNumber,
    OrderType? orderType,
    OrderStatus? status,
    String? customerId,
    Money? subtotal,
    Money? discountAmount,
    Money? taxAmount,
    Money? totalAmount,
    String? notes,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
  }) {
    return Order(
      id: id,
      orderNumber: orderNumber ?? this.orderNumber,
      orderType: orderType ?? this.orderType,
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      SyncColumns.id: id,
      SyncColumns.createdAt: SqliteValue.fromDateTime(createdAt),
      SyncColumns.updatedAt: SqliteValue.fromDateTime(updatedAt),
      SyncColumns.isDeleted: SqliteValue.fromBool(isDeleted),
      SyncColumns.syncState: syncState.name,
      'orderNumber': orderNumber,
      'orderType': orderType.name,
      'status': status.name,
      'customerId': customerId,
      'subtotalPaise': subtotal.paise,
      'discountAmountPaise': discountAmount.paise,
      'taxAmountPaise': taxAmount.paise,
      'totalAmountPaise': totalAmount.paise,
      'notes': notes,
    };
  }
}
