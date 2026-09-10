import '../../../../core/data/local/sqlite/row.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/data/sync/syncable_entity.dart';
import '../../../../core/money/money.dart';
import 'menu_option_type.dart';

/// A selectable customisation such as Thin Crust, Extra Cheese or Ketchup.
///
/// These are database rows, never constants in a widget. The outlet changes its
/// add-on prices without a rebuild, and a bill printed last month must still show
/// the price that applied then, which only works if the value has a home in the
/// data layer.
class MenuItemOption implements SyncableEntity {
  const MenuItemOption({
    required this.id,
    required this.name,
    required this.optionType,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
    this.menuItemId,
    this.displayOrder = 0,
    this.isActive = true,
    this.isDeleted = false,
    this.syncState = SyncState.pending,
  });

  factory MenuItemOption.fromRow(Map<String, Object?> row) {
    return MenuItemOption(
      id: row.requireString(SyncColumns.id),
      menuItemId: row.optionalString('menuItemId'),
      name: row.requireString('name'),
      optionType: row.requireEnum<MenuOptionType>(
        'optionType',
        MenuOptionType.values,
        fallback: MenuOptionType.addOn,
      ),
      price: Money.fromPaise(row.requireInt('pricePaise')),
      displayOrder: row.optionalInt('displayOrder'),
      isActive: row.requireBool('isActive'),
      createdAt: row.requireDateTime(SyncColumns.createdAt),
      updatedAt: row.requireDateTime(SyncColumns.updatedAt),
      isDeleted: row.requireBool(SyncColumns.isDeleted),
      syncState: row.requireSyncState(SyncColumns.syncState),
    );
  }

  @override
  final String id;

  /// `null` when the option applies to every product, which is how a global
  /// add-on like Extra Cheese is stored: once, not duplicated per pizza.
  final String? menuItemId;

  final String name;

  final MenuOptionType optionType;

  /// Amount added to the line when selected. May be zero for a genuinely free
  /// option, but zero must be a deliberate decision rather than a missing value.
  final Money price;

  final int displayOrder;

  final bool isActive;

  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final bool isDeleted;

  @override
  final SyncState syncState;

  /// True when this option can be offered on every product.
  bool get isGlobal => menuItemId == null;

  MenuItemOption copyWith({
    String? menuItemId,
    String? name,
    MenuOptionType? optionType,
    Money? price,
    int? displayOrder,
    bool? isActive,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncState? syncState,
  }) {
    return MenuItemOption(
      id: id,
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      optionType: optionType ?? this.optionType,
      price: price ?? this.price,
      displayOrder: displayOrder ?? this.displayOrder,
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
      'menuItemId': menuItemId,
      'name': name,
      'optionType': optionType.name,
      'pricePaise': price.paise,
      'displayOrder': displayOrder,
      'isActive': SqliteValue.fromBool(isActive),
    };
  }
}
