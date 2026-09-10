import 'package:sqflite/sqflite.dart';

import '../../../../core/data/local/sqlite/sqlite_database.dart';
import '../../../../core/data/local/sqlite/sqlite_error_mapper.dart';
import '../../../../core/data/local/sqlite/sqlite_local_store.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/utils/result.dart';
import '../../domain/models/menu_category.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/menu_item_option.dart';
import '../../domain/models/menu_item_variant.dart';
import '../../domain/repositories/menu_repository.dart';

/// SQLite implementation of [MenuRepository].
///
/// Generic CRUD is delegated to [SqliteLocalStore]; the queries below are the ones
/// that are genuinely menu-shaped, such as resolving which options apply to an
/// item. All SQL for the menu lives in this file and nowhere else.
class SqliteMenuRepository implements MenuRepository {
  SqliteMenuRepository({required SqliteDatabase database})
    : _database = database,
      _categories = SqliteLocalStore<MenuCategory>(
        database: database,
        table: SqliteTables.categories,
        fromRow: MenuCategory.fromRow,
        orderBy: 'displayOrder ASC, name ASC',
      ),
      _items = SqliteLocalStore<MenuItem>(
        database: database,
        table: SqliteTables.menuItems,
        fromRow: MenuItem.fromRow,
        orderBy: 'displayOrder ASC, name ASC',
      ),
      _variants = SqliteLocalStore<MenuItemVariant>(
        database: database,
        table: SqliteTables.menuItemVariants,
        fromRow: MenuItemVariant.fromRow,
        orderBy: 'displayOrder ASC',
      ),
      _options = SqliteLocalStore<MenuItemOption>(
        database: database,
        table: SqliteTables.menuItemOptions,
        fromRow: MenuItemOption.fromRow,
        orderBy: 'displayOrder ASC, name ASC',
      );

  final SqliteDatabase _database;
  final SqliteLocalStore<MenuCategory> _categories;
  final SqliteLocalStore<MenuItem> _items;
  final SqliteLocalStore<MenuItemVariant> _variants;
  final SqliteLocalStore<MenuItemOption> _options;

  Database get _db => _database.database;

  @override
  Future<Result<List<MenuCategory>>> loadCategories() {
    return SqliteErrorMapper.guard<List<MenuCategory>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.categories,
        where: 'isDeleted = 0 AND isActive = 1',
        orderBy: 'displayOrder ASC, name ASC',
      );
      return rows.map(MenuCategory.fromRow).toList(growable: false);
    }, context: 'load the menu categories');
  }

  @override
  Stream<List<MenuCategory>> watchCategories() => _categories.watchAll();

  @override
  Future<Result<List<MenuItem>>> loadItems({String? categoryId}) {
    return SqliteErrorMapper.guard<List<MenuItem>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.menuItems,
        where: categoryId == null
            ? 'isDeleted = 0 AND isActive = 1'
            : 'isDeleted = 0 AND isActive = 1 AND categoryId = ?',
        whereArgs: categoryId == null ? null : <Object?>[categoryId],
        orderBy: 'displayOrder ASC, name ASC',
      );
      return rows.map(MenuItem.fromRow).toList(growable: false);
    }, context: 'load the menu items');
  }

  @override
  Future<Result<MenuItem?>> findItem(String id) => _items.findById(id);

  @override
  Future<Result<List<MenuItemVariant>>> loadVariants(String menuItemId) {
    return SqliteErrorMapper.guard<List<MenuItemVariant>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.menuItemVariants,
        where: 'isDeleted = 0 AND isActive = 1 AND menuItemId = ?',
        whereArgs: <Object?>[menuItemId],
        orderBy: 'displayOrder ASC',
      );
      return rows.map(MenuItemVariant.fromRow).toList(growable: false);
    }, context: 'load the item sizes');
  }

  @override
  Future<Result<List<MenuItemOption>>> loadOptionsForItem(String menuItemId) {
    return SqliteErrorMapper.guard<List<MenuItemOption>>(() async {
      // A NULL menuItemId means the option applies to every product, so the
      // item's own options and the global ones are returned as one list.
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.menuItemOptions,
        where:
            'isDeleted = 0 AND isActive = 1 '
            'AND (menuItemId = ? OR menuItemId IS NULL)',
        whereArgs: <Object?>[menuItemId],
        orderBy: 'optionType ASC, displayOrder ASC, name ASC',
      );
      return rows.map(MenuItemOption.fromRow).toList(growable: false);
    }, context: 'load the item options');
  }

  @override
  Future<Result<List<MenuItemOption>>> loadAllOptions() {
    return SqliteErrorMapper.guard<List<MenuItemOption>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.menuItemOptions,
        where: 'isDeleted = 0 AND isActive = 1',
        orderBy: 'optionType ASC, displayOrder ASC, name ASC',
      );
      return rows.map(MenuItemOption.fromRow).toList(growable: false);
    }, context: 'load the menu options');
  }

  @override
  Future<Result<void>> saveCategory(MenuCategory category) =>
      _categories.save(category);

  @override
  Future<Result<void>> saveItem(MenuItem item) => _items.save(item);

  @override
  Future<Result<void>> saveVariant(MenuItemVariant variant) =>
      _variants.save(variant);

  @override
  Future<Result<void>> saveOption(MenuItemOption option) =>
      _options.save(option);

  @override
  Future<Result<void>> deleteCategory(String id) => _categories.softDelete(id);

  @override
  Future<Result<void>> deleteItem(String id) => _items.softDelete(id);
}
