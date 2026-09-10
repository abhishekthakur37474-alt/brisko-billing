import '../../../../core/data/local/sqlite/row.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/data/sync/syncable_entity.dart';
import 'kot_status.dart';

/// A kitchen order ticket: the record of what was sent to the kitchen.
///
/// An order can have several tickets, because items added after the first slip went
/// back need their own slip rather than a reprint of the whole order. That is why
/// this is a separate table keyed on `orderId` instead of a status column on the
/// order.
///
/// Printing is not implemented here. This records the intent and the outcome; the
/// thermal printer integration is a later step.
class KotRecord implements SyncableEntity {
  const KotRecord({
    required this.id,
    required this.orderId,
    required this.kotNumber,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.syncState = SyncState.pending,
  });

  factory KotRecord.fromRow(Map<String, Object?> row) {
    return KotRecord(
      id: row.requireString(SyncColumns.id),
      orderId: row.requireString('orderId'),
      kotNumber: row.requireString('kotNumber'),
      status: row.requireEnum<KotStatus>(
        'status',
        KotStatus.values,
        fallback: KotStatus.pending,
      ),
      createdAt: row.requireDateTime(SyncColumns.createdAt),
      updatedAt: row.requireDateTime(SyncColumns.updatedAt),
      isDeleted: row.requireBool(SyncColumns.isDeleted),
      syncState: row.requireSyncState(SyncColumns.syncState),
    );
  }

  @override
  final String id;

  final String orderId;

  /// Number printed on the slip so the counter and kitchen can refer to it aloud.
  final String kotNumber;

  final KotStatus status;

  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final bool isDeleted;

  @override
  final SyncState syncState;

  KotRecord copyWith({
    KotStatus? status,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
  }) {
    return KotRecord(
      id: id,
      orderId: orderId,
      kotNumber: kotNumber,
      status: status ?? this.status,
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
      'orderId': orderId,
      'kotNumber': kotNumber,
      'status': status.name,
    };
  }
}
