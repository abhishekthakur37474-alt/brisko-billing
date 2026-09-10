/// Why stock moved.
///
/// The sign of the movement is derived from the type rather than stored, so a
/// wastage entry cannot accidentally be recorded as an increase.
enum StockMovementType {
  /// Stock received from a supplier. Increases quantity.
  purchase,

  /// Consumed by selling an item. Decreases quantity.
  sale,

  /// Correction after a physical count. Signed by the recorded quantity, since a
  /// count can go either way.
  adjustment,

  /// Spoiled, dropped or otherwise lost. Decreases quantity.
  wastage;

  String get label => switch (this) {
    StockMovementType.purchase => 'Purchase',
    StockMovementType.sale => 'Sale',
    StockMovementType.adjustment => 'Adjustment',
    StockMovementType.wastage => 'Wastage',
  };

  /// How this movement affects the running quantity: `1` to add, `-1` to subtract,
  /// or `0` when the recorded quantity already carries its own sign.
  int get direction => switch (this) {
    StockMovementType.purchase => 1,
    StockMovementType.sale => -1,
    StockMovementType.wastage => -1,
    StockMovementType.adjustment => 0,
  };
}
