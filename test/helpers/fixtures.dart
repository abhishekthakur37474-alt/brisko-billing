import 'package:brisko_billing/core/money/money.dart';
import 'package:brisko_billing/core/utils/entity_id.dart';
import 'package:brisko_billing/features/customers/domain/models/customer.dart';
import 'package:brisko_billing/features/inventory/domain/models/inventory_item.dart';
import 'package:brisko_billing/features/kot/domain/models/kot_item.dart';
import 'package:brisko_billing/features/kot/domain/models/kot_record.dart';
import 'package:brisko_billing/features/kot/domain/models/kot_status.dart';
import 'package:brisko_billing/features/menu/domain/models/menu_category.dart';
import 'package:brisko_billing/features/menu/domain/models/menu_item.dart';
import 'package:brisko_billing/features/menu/domain/models/menu_item_option.dart';
import 'package:brisko_billing/features/menu/domain/models/menu_item_type.dart';
import 'package:brisko_billing/features/menu/domain/models/menu_item_variant.dart';
import 'package:brisko_billing/features/menu/domain/models/menu_option_type.dart';
import 'package:brisko_billing/features/orders/domain/models/order.dart';
import 'package:brisko_billing/features/orders/domain/models/order_item.dart';
import 'package:brisko_billing/features/orders/domain/models/order_item_option.dart';
import 'package:brisko_billing/features/orders/domain/models/order_status.dart';
import 'package:brisko_billing/features/orders/domain/models/order_type.dart';
import 'package:brisko_billing/features/payments/domain/models/payment.dart';
import 'package:brisko_billing/features/payments/domain/models/payment_method.dart';
import 'package:brisko_billing/features/payments/domain/models/payment_status.dart';

/// Builders for test entities.
///
/// The names and prices here are obviously synthetic ("Test Pizza", 100.00) so that
/// no reader could mistake them for the outlet's real menu. Real product data lives
/// only in the seed migration, and tests never depend on it beyond the category
/// names the owner supplied.
class Fixtures {
  const Fixtures._();

  static DateTime get _now => DateTime.now().toUtc();

  static MenuCategory category({
    String? id,
    String name = 'Test Category',
    int displayOrder = 1,
    bool isActive = true,
  }) {
    return MenuCategory(
      id: id ?? EntityId.generate(prefix: 'cat'),
      name: name,
      displayOrder: displayOrder,
      isActive: isActive,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static MenuItem menuItem({
    required String categoryId,
    String? id,
    String name = 'Test Pizza',
    String basePrice = '100.00',
    MenuItemType itemType = MenuItemType.veg,
    bool isAvailable = true,
  }) {
    return MenuItem(
      id: id ?? EntityId.generate(prefix: 'item'),
      categoryId: categoryId,
      name: name,
      itemType: itemType,
      basePrice: Money.parse(basePrice),
      isAvailable: isAvailable,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static MenuItemVariant variant({
    required String menuItemId,
    String? id,
    String name = 'Medium',
    String price = '200.00',
    int displayOrder = 2,
  }) {
    return MenuItemVariant(
      id: id ?? EntityId.generate(prefix: 'var'),
      menuItemId: menuItemId,
      name: name,
      price: Money.parse(price),
      displayOrder: displayOrder,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static MenuItemOption option({
    String? id,
    String? menuItemId,
    String? variantId,
    String? categoryId,
    String name = 'Extra Cheese',
    MenuOptionType optionType = MenuOptionType.addOn,
    String price = '30.00',
    int displayOrder = 0,
  }) {
    return MenuItemOption(
      id: id ?? EntityId.generate(prefix: 'opt'),
      menuItemId: menuItemId,
      variantId: variantId,
      categoryId: categoryId,
      name: name,
      optionType: optionType,
      price: Money.parse(price),
      displayOrder: displayOrder,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static Customer customer({
    String? id,
    String phone = '9000000001',
    String? name = 'Test Customer',
  }) {
    return Customer(
      id: id ?? EntityId.generate(prefix: 'cus'),
      name: name,
      phone: phone,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static Order order({
    required String orderNumber,
    String? id,
    OrderType orderType = OrderType.takeaway,
    OrderStatus status = OrderStatus.confirmed,
    String? customerId,
    String subtotal = '200.00',
    String discount = '0.00',
    String tax = '10.00',
    String total = '210.00',
    String? notes,
  }) {
    return Order(
      id: id ?? EntityId.generate(prefix: 'ord'),
      orderNumber: orderNumber,
      orderType: orderType,
      status: status,
      customerId: customerId,
      subtotal: Money.parse(subtotal),
      discountAmount: Money.parse(discount),
      taxAmount: Money.parse(tax),
      totalAmount: Money.parse(total),
      notes: notes,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static OrderItem orderItem({
    required String orderId,
    String? id,
    String? menuItemId,
    String itemName = 'Test Pizza',
    String? variantName = 'Medium',
    int quantity = 2,
    String unitPrice = '100.00',
    String total = '200.00',
    String? notes,
  }) {
    return OrderItem(
      id: id ?? EntityId.generate(prefix: 'oit'),
      orderId: orderId,
      menuItemId: menuItemId,
      itemNameSnapshot: itemName,
      variantNameSnapshot: variantName,
      quantity: quantity,
      unitPrice: Money.parse(unitPrice),
      totalAmount: Money.parse(total),
      notes: notes,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static OrderItemOption orderItemOption({
    required String orderItemId,
    String? id,
    String optionName = 'Extra Cheese',
    String price = '30.00',
    int quantity = 1,
  }) {
    return OrderItemOption(
      id: id ?? EntityId.generate(prefix: 'oio'),
      orderItemId: orderItemId,
      optionNameSnapshot: optionName,
      price: Money.parse(price),
      quantity: quantity,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static Payment payment({
    required String orderId,
    String? id,
    PaymentMethod method = PaymentMethod.upi,
    String amount = '210.00',
    PaymentStatus status = PaymentStatus.completed,
    String? reference = 'TEST-REF-1',
  }) {
    return Payment(
      id: id ?? EntityId.generate(prefix: 'pay'),
      orderId: orderId,
      paymentMethod: method,
      amount: Money.parse(amount),
      reference: reference,
      status: status,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static InventoryItem inventoryItem({
    String? id,
    String name = 'Test Cheese',
    String unit = 'kg',
    String currentQuantity = '10',
    String minimumQuantity = '2',
  }) {
    return InventoryItem(
      id: id ?? EntityId.generate(prefix: 'inv'),
      name: name,
      unit: unit,
      currentQuantityMilli: InventoryItem.parseQuantity(currentQuantity),
      minimumQuantityMilli: InventoryItem.parseQuantity(minimumQuantity),
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static KotRecord kotRecord({
    required String orderId,
    required String kotNumber,
    String? id,
    KotStatus status = KotStatus.pending,
  }) {
    return KotRecord(
      id: id ?? EntityId.generate(prefix: 'kot'),
      orderId: orderId,
      kotNumber: kotNumber,
      status: status,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  static KotItem kotItem({
    required String kotId,
    required String orderItemId,
    String? id,
    String itemName = 'Test Pizza',
    String? variantName = 'Medium',
    int quantity = 2,
    String? notes,
  }) {
    return KotItem(
      id: id ?? EntityId.generate(prefix: 'kit'),
      kotId: kotId,
      orderItemId: orderItemId,
      itemNameSnapshot: itemName,
      variantNameSnapshot: variantName,
      quantity: quantity,
      notes: notes,
      createdAt: _now,
      updatedAt: _now,
    );
  }
}
