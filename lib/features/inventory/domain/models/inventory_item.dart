import '../../../../core/data/local/sqlite/row.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/data/sync/syncable_entity.dart';

/// A tracked stock item, such as flour or cheese.
///
/// ## Quantity representation
///
/// Quantities are exact integer thousandths of the unit, held in
/// [currentQuantityMilli]. `2.5 kg` is `2500`.
///
/// The reasoning matches money: stock arrives and is consumed in fractional
/// amounts, and a running balance updated with `double` accumulates error until the
/// recorded quantity stops matching the shelf. Thousandths give three decimal
/// places, which covers grams within a kilogram and millilitres within a litre.
///
/// There is no recipe or ingredient linkage yet, so nothing deducts stock
/// automatically. Movements are recorded explicitly.
class InventoryItem implements SyncableEntity {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.createdAt,
    required this.updatedAt,
    this.currentQuantityMilli = 0,
    this.minimumQuantityMilli = 0,
    this.isActive = true,
    this.isDeleted = false,
    this.syncState = SyncState.pending,
  });

  factory InventoryItem.fromRow(Map<String, Object?> row) {
    return InventoryItem(
      id: row.requireString(SyncColumns.id),
      name: row.requireString('name'),
      unit: row.requireString('unit'),
      currentQuantityMilli: row.optionalInt('currentQuantityMilli'),
      minimumQuantityMilli: row.optionalInt('minimumQuantityMilli'),
      isActive: row.requireBool('isActive'),
      createdAt: row.requireDateTime(SyncColumns.createdAt),
      updatedAt: row.requireDateTime(SyncColumns.updatedAt),
      isDeleted: row.requireBool(SyncColumns.isDeleted),
      syncState: row.requireSyncState(SyncColumns.syncState),
    );
  }

  /// Converts a display quantity such as `2.5` into thousandths.
  ///
  /// Takes a string rather than a number so no `double` ever enters the stock
  /// ledger. Throws [FormatException] on a value with more than three decimals.
  static int parseQuantity(String value) {
    final RegExpMatch? match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,3}))?$')
        .firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Not a valid quantity', value);
    }
    final int whole = int.parse(match.group(2)!);
    final String fraction = (match.group(3) ?? '').padRight(3, '0');
    final int total =
        whole * 1000 + int.parse(fraction.isEmpty ? '0' : fraction);
    return match.group(1) == '-' ? -total : total;
  }

  /// Renders thousandths as a trimmed decimal string, for example `2.5`.
  static String formatQuantity(int milli) {
    final int absolute = milli.abs();
    final String whole = (absolute ~/ 1000).toString();
    final String fraction = (absolute % 1000)
        .toString()
        .padLeft(3, '0')
        .replaceAll(RegExp(r'0+$'), '');
    final String sign = milli.isNegative ? '-' : '';
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }

  @override
  final String id;

  final String name;

  /// Unit of measure as free text, for example `kg`, `litre`, `piece`.
  final String unit;

  /// Running balance, in thousandths of [unit].
  final int currentQuantityMilli;

  /// Threshold below which the item is reported as low, in thousandths.
  final int minimumQuantityMilli;

  final bool isActive;

  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final bool isDeleted;

  @override
  final SyncState syncState;

  /// True when the balance has fallen to or below the reorder threshold. A
  /// threshold of zero means the item is not monitored.
  bool get isLow =>
      minimumQuantityMilli > 0 && currentQuantityMilli <= minimumQuantityMilli;

  String get currentQuantityDisplay => formatQuantity(currentQuantityMilli);

  InventoryItem copyWith({
    String? name,
    String? unit,
    int? currentQuantityMilli,
    int? minimumQuantityMilli,
    bool? isActive,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
  }) {
    return InventoryItem(
      id: id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      currentQuantityMilli: currentQuantityMilli ?? this.currentQuantityMilli,
      minimumQuantityMilli: minimumQuantityMilli ?? this.minimumQuantityMilli,
      isActive: isActive ?? this.isActive,
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
      'name': name,
      'unit': unit,
      'currentQuantityMilli': currentQuantityMilli,
      'minimumQuantityMilli': minimumQuantityMilli,
      'isActive': SqliteValue.fromBool(isActive),
    };
  }
}
