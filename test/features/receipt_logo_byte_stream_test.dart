import 'package:brisko_billing/core/money/money.dart';
import 'package:brisko_billing/features/orders/domain/models/order_type.dart';
import 'package:brisko_billing/features/payments/domain/models/payment_method.dart';
import 'package:brisko_billing/features/printing/data/escpos/escpos_commands.dart';
import 'package:brisko_billing/features/printing/data/escpos/escpos_document_formatter.dart';
import 'package:brisko_billing/features/printing/domain/models/business_identity.dart';
import 'package:brisko_billing/features/printing/domain/models/monochrome_bitmap.dart';
import 'package:brisko_billing/features/printing/domain/models/print_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/escpos_transcript.dart';

/// Byte-level regression for the logo raster defect (Step 19 / Step 7).
///
/// The physical symptom was a block of garbage characters above `BRISKO PIZZA`: the
/// whole 240×240 logo went out as one `GS v 0` whose 7200-byte payload overran the
/// printer's input buffer, so the printer fell out of raster mode and printed the
/// remaining image bytes as text. This test generates a complete receipt through the
/// real encoder and parses the byte stream to prove the logo is now framed as
/// buffer-safe bands and that the receipt text begins cleanly after the image — nothing
/// the printer could read as characters leaks out of the raster payload.
void main() {
  /// A 240×240 logo, the size the bundled Brisko PNG is reduced to. A dense pattern so
  /// the payload is full-size, not sparse.
  MonochromeBitmap logo240() => MonochromeBitmap.fromPixels(
    width: 240,
    pixels: List<List<bool>>.generate(
      240,
      (int y) => List<bool>.generate(240, (int x) => ((x ~/ 3) + (y ~/ 3)).isEven),
    ),
  );

  CustomerReceipt fullReceipt() {
    final Money price = Money.parse('400.00');
    return CustomerReceipt(
      business: BusinessIdentity(
        name: 'BRISKO PIZZA',
        address: '12 Main Road',
        phone: '080-1234-5678',
        feedbackUrl: 'https://brisko.example/review/42',
        logo: logo240(),
      ),
      orderNumber: '20260915-0007',
      orderType: OrderType.takeaway,
      issuedAt: DateTime.utc(2026, 9, 15, 13, 2),
      lines: <CustomerReceiptLine>[
        CustomerReceiptLine(
          name: 'Cheese Pizza',
          variantName: 'Large',
          quantity: 1,
          unitPrice: price,
          lineTotal: price,
        ),
      ],
      totals: CustomerReceiptTotals(
        subtotal: price,
        discount: Money.parse('40.00'),
        tax: Money.parse('64.80'),
        total: Money.parse('424.80'),
        discountLabel: '10%',
      ),
      paymentMethod: PaymentMethod.upi,
    );
  }

  const EscPosDocumentFormatter formatter = EscPosDocumentFormatter();

  group('the real receipt byte stream carries a well-framed logo', () {
    test('the logo is emitted as more than one buffer-safe band', () {
      final EscPosTranscript paper = EscPosTranscript.of(
        formatter.encode(fullReceipt()),
      );

      expect(paper.rasterImages.length, greaterThan(1));
      for (final EscPosRasterImage band in paper.rasterImages) {
        // Header and payload agree exactly, and the payload stays under the buffer
        // budget that caused the overrun.
        expect(band.data, hasLength(band.expectedByteCount));
        expect(band.widthBytes, 30);
        expect(
          band.data.length,
          lessThanOrEqualTo(EscPosCommands.rasterMaxBandBytes),
        );
      }
    });

    test('the bands stitch back to a full 240×240, 7200-byte image', () {
      final EscPosTranscript paper = EscPosTranscript.of(
        formatter.encode(fullReceipt()),
      );

      final EscPosRasterImage stitched = paper.logo!;
      expect(stitched.widthBytes, 30);
      expect(stitched.heightDots, 240);
      expect(stitched.data, hasLength(30 * 240)); // 7200
    });

    test('the logo prints before BRISKO PIZZA, with no garbage between', () {
      final EscPosTranscript paper = EscPosTranscript.of(
        formatter.encode(fullReceipt()),
      );

      // The first raster header comes before the outlet name is printed.
      final int logoAt = paper.commands.indexWhere(
        (List<int> c) => c.length >= 2 && c[0] == EscPosCommands.gs && c[1] == 0x76,
      );
      expect(logoAt, greaterThanOrEqualTo(0));

      // BRISKO PIZZA is a clean printed line: the image payload did not leak into text.
      expect(paper.hasLineContaining('BRISKO PIZZA'), isTrue);

      // Nothing prints as text ahead of the outlet name. The only lines before it are
      // the blank line the image itself ends on; there is no run of stray characters.
      final int nameLine = paper.lines.indexWhere(
        (String line) => line.contains('BRISKO PIZZA'),
      );
      for (int i = 0; i < nameLine; i++) {
        expect(
          paper.lines[i].trim(),
          isEmpty,
          reason: 'no garbage should print above the outlet name',
        );
      }
    });

    test('the receipt still carries the feedback QR and the GST/discount lines', () {
      final EscPosTranscript paper = EscPosTranscript.of(
        formatter.encode(fullReceipt()),
      );

      // Feedback QR intact.
      expect(paper.qrPayloads, contains('https://brisko.example/review/42'));
      // GST split and the discount survive alongside the banded logo.
      expect(paper.hasLineContaining('CGST'), isTrue);
      expect(paper.hasLineContaining('SGST'), isTrue);
      expect(paper.hasLineContaining('Discount'), isTrue);
      expect(paper.hasLineContaining('Taxable amount'), isTrue);
      expect(paper.hasLineContaining('TOTAL INR'), isTrue);
    });

    test('a receipt with no logo emits no raster command at all', () {
      final EscPosTranscript paper = EscPosTranscript.of(
        formatter.encode(
          CustomerReceipt(
            business: const BusinessIdentity(name: 'BRISKO PIZZA'),
            orderNumber: '20260915-0008',
            orderType: OrderType.dineIn,
            issuedAt: DateTime.utc(2026, 9, 15, 13, 2),
            lines: <CustomerReceiptLine>[
              CustomerReceiptLine(
                name: 'Cheese Pizza',
                quantity: 1,
                unitPrice: Money.parse('400.00'),
                lineTotal: Money.parse('400.00'),
              ),
            ],
            totals: CustomerReceiptTotals(
              subtotal: Money.parse('400.00'),
              discount: Money.zero,
              tax: Money.zero,
              total: Money.parse('400.00'),
            ),
            paymentMethod: PaymentMethod.cash,
          ),
        ),
      );

      expect(paper.rasterImages, isEmpty);
    });
  });
}
