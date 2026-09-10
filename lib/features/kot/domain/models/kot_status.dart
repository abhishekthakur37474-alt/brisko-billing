/// Where a kitchen slip stands.
///
/// The kitchen has no screen and no printer of its own, so these states are set by
/// the terminal, not by the kitchen. [printed] records that a paper slip was
/// produced on the shared thermal printer; [completed] is the cashier marking the
/// food as done.
enum KotStatus {
  /// Created but not yet printed. A slip in this state is the actionable one.
  pending,

  printed,

  completed,

  cancelled;

  String get label => switch (this) {
    KotStatus.pending => 'Pending',
    KotStatus.printed => 'Printed',
    KotStatus.completed => 'Completed',
    KotStatus.cancelled => 'Cancelled',
  };

  /// True when the slip still needs to reach the kitchen on paper.
  bool get needsPrinting => this == KotStatus.pending;
}
