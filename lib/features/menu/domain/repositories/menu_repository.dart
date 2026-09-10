import '../../../../core/utils/result.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_item_option.dart';
import '../models/menu_item_variant.dart';

/// Read and write access to the menu.
///
/// Abstract so that the billing module can be written and tested against it
/// without a database, and so that no feature learns that SQLite exists.
abstract interface class MenuRepository {
  /// Active categories in display order.
  Future<Result<List<MenuCategory>>> loadCategories();

  /// Emits the category list whenever it changes.
  Stream<List<MenuCategory>> watchCategories();

  /// Active items, optionally restricted to one category.
  Future<Result<List<MenuItem>>> loadItems({String? categoryId});

  Future<Result<MenuItem?>> findItem(String id);

  /// Sizes for one item, in display order. Empty for a single-price item.
  Future<Result<List<MenuItemVariant>>> loadVariants(String menuItemId);

  /// Options offered on [menuItemId]: those scoped to the item plus every global
  /// option.
  ///
  /// The union happens here rather than in the caller so that no screen has to
  /// know that a `null` `menuItemId` on an option means "applies to everything".
  Future<Result<List<MenuItemOption>>> loadOptionsForItem(String menuItemId);

  /// Every active option, scoped and global.
  Future<Result<List<MenuItemOption>>> loadAllOptions();

  Future<Result<void>> saveCategory(MenuCategory category);

  Future<Result<void>> saveItem(MenuItem item);

  Future<Result<void>> saveVariant(MenuItemVariant variant);

  Future<Result<void>> saveOption(MenuItemOption option);

  Future<Result<void>> deleteCategory(String id);

  Future<Result<void>> deleteItem(String id);
}
