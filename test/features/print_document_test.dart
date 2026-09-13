import 'package:brisko_billing/core/money/money.dart';
import 'package:brisko_billing/features/orders/domain/models/order_type.dart';
import 'package:brisko_billing/features/payments/domain/models/payment_method.dart';
import 'package:brisko_billing/features/printing/data/escpos/escpos_commands.dart';
import 'package:brisko_billing/features/printing/data/escpos/escpos_document_formatter.dart';
import 'package:brisko_billing/features/printing/domain/models/business_identity.dart';
import 'package:brisko_billing/features/printing/domain/models/paper_width.dart';
import 'package:brisko_billing/features/printing/domain/models/print_document.dart';
import 'package:brisko_billing/features/printing/domain/models/print_profile.dart';
import 'package:brisko_billing/features/printing/domain/models/printer_capabilities.dart';
import 'package:brisko_billing/features/printing/domain/models/upi_payment_request.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/escpos_transcript.dart';

/// The two documents the outlet prints, read back as the kitchen and the customer would
/// read them.
///
/// Documents are built here by hand because that is what they are: flat descriptions of
/// a piece of paper. Building them from the database is the document source's job and is
/// covered by the print service tests; these are about the layout, and specifically about
/// the two rules that matter most — a receipt shows exact money, and a kitchen slip shows
/// none.
void main() {
  const int columns = 48;
  const EscPosDocumentFormatter formatter = EscPosDocumentFormatter();

  final DateTime issuedAt = DateTime.utc(2026, 9, 11, 9, 0);

  EscPosTranscript print(PrintDocument document) =>
      EscPosTranscript.of(formatter.encode(document));

  CustomerReceipt receipt({
    BusinessIdentity business = BusinessIdentity.unconfigured,
    List<CustomerReceiptLine>? lines,
    CustomerReceiptTotals? totals,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? customerPhone,
    UpiPaymentRequest? upiPayment,
    String? notes,
    OrderType orderType = OrderType.takeaway,
    bool isReprint = false,
  }) {
    final List<CustomerReceiptLine> resolved =
        lines ??
        <CustomerReceiptLine>[
          CustomerReceiptLine(
            name: 'Cheese Pizza',
            variantName: 'Medium',
            quantity: 1,
            unitPrice: Money.parse('320.00'),
            lineTotal: Money.parse('320.00'),
            options: <CustomerReceiptLineOption>[
              CustomerReceiptLineOption(
                name: 'Extra Cheese',
                price: Money.parse('70.00'),
              ),
            ],
          ),
        ];

    final Money subtotal = Money.sum(
      resolved.map((CustomerReceiptLine line) => line.lineTotal),
    );

    return CustomerReceipt(
      business: business,
      orderNumber: '20260911-0001',
      orderType: orderType,
      issuedAt: issuedAt,
      lines: resolved,
      totals:
          totals ??
          CustomerReceiptTotals(
            subtotal: subtotal,
            discount: Money.zero,
            tax: Money.zero,
            total: subtotal,
          ),
      paymentMethod: paymentMethod,
      customerPhone: customerPhone,
      upiPayment: upiPayment,
      notes: notes,
      isReprint: isReprint,
    );
  }

  KitchenKot kot({
    List<KitchenKotLine>? lines,
    String? notes,
    OrderType orderType = OrderType.dineIn,
    bool isReprint = false,
  }) {
    return KitchenKot(
      kotNumber: 'K20260911-0001',
      orderNumber: '20260911-0001',
      orderType: orderType,
      issuedAt: issuedAt,
      notes: notes,
      isReprint: isReprint,
      lines:
          lines ??
          const <KitchenKotLine>[
            KitchenKotLine(
              name: 'Cheese Pizza',
              variantName: 'Medium',
              quantity: 2,
              options: <String>['Extra Cheese'],
            ),
          ],
    );
  }

  group('the customer receipt', () {
    test('the outlet name heads the bill', () {
      final EscPosTranscript paper = print(receipt());

      expect(paper.lines.first, BusinessIdentity.defaultName);
      expect(paper.hasCommand(EscPosCommands.sizeDoubleHeight), isTrue);
    });

    test('configured outlet details are printed', () {
      final EscPosTranscript paper = print(
        receipt(
          business: const BusinessIdentity(
            name: 'Brisko Pizza Kothrud',
            address: '12 Paud Road, Pune 411038',
            phone: '02012345678',
            gstin: '27ABCDE1234F1Z5',
            receiptHeader: 'Dine-in and takeaway',
            receiptFooter: 'Thank you, please come again',
          ),
        ),
      );

      expect(paper.hasLineContaining('Brisko Pizza Kothrud'), isTrue);
      expect(paper.hasLineContaining('12 Paud Road, Pune 411038'), isTrue);
      expect(paper.hasLineContaining('Phone 02012345678'), isTrue);
      expect(paper.hasLineContaining('GSTIN 27ABCDE1234F1Z5'), isTrue);
      expect(paper.hasLineContaining('Dine-in and takeaway'), isTrue);
      expect(paper.hasLineContaining('Thank you, please come again'), isTrue);
    });

    test('an unconfigured outlet claims nothing it has not been told', () {
      // No invented address, telephone number or GSTIN. A blank setting produces a
      // blank space, because a placeholder tax number on an invoice is worse than none.
      final EscPosTranscript paper = print(receipt());

      expect(paper.text, isNot(contains('GSTIN')));
      expect(paper.text, isNot(contains('Phone')));
      expect(paper.hasLineContaining('Brisko Pizza'), isTrue);
    });

    test('the bill carries its number, the time and the order type', () {
      final EscPosTranscript paper = print(
        receipt(orderType: OrderType.delivery),
      );

      final String header = paper.lineContaining('Bill 20260911-0001')!;
      expect(header, contains('Delivery'));
      expect(header.length, columns);
      expect(paper.hasLineContaining('11/09/2026'), isTrue);
    });

    test('the customer phone is printed when one was taken', () {
      expect(
        print(receipt(customerPhone: '9876543210'))
            .hasLineContaining('Customer: 9876543210'),
        isTrue,
      );
    });

    test('a walk-in gets no customer line', () {
      expect(print(receipt()).text, isNot(contains('Customer:')));
    });

    test('a line shows the size, its options, the quantity and the total', () {
      final EscPosTranscript paper = print(receipt());

      expect(paper.hasLineContaining('Cheese Pizza (Medium)'), isTrue);
      expect(paper.hasLineContaining('+ Extra Cheese'), isTrue);
      final String quantity = paper.lineContaining('1 x 320.00')!;
      expect(quantity.endsWith('320.00'), isTrue);
    });

    test('several quantities of one line reconcile on the paper', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name: 'Cheese Pizza',
              variantName: 'Medium',
              quantity: 3,
              unitPrice: Money.parse('320.00'),
              lineTotal: Money.parse('960.00'),
              options: <CustomerReceiptLineOption>[
                CustomerReceiptLineOption(
                  name: 'Extra Cheese',
                  price: Money.parse('70.00'),
                  quantity: 3,
                ),
              ],
            ),
          ],
        ),
      );

      final String quantity = paper.lineContaining('3 x 320.00')!;
      expect(quantity.endsWith('960.00'), isTrue);
      expect(paper.hasLineContaining('Subtotal'), isTrue);
      expect(paper.lineContaining('Subtotal')!.endsWith('960.00'), isTrue);
      expect(paper.lineContaining('TOTAL')!.endsWith('960.00'), isTrue);
    });

    test('several lines each keep their own options', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name: 'Cheese Pizza',
              variantName: 'Medium',
              quantity: 1,
              unitPrice: Money.parse('320.00'),
              lineTotal: Money.parse('320.00'),
              options: <CustomerReceiptLineOption>[
                CustomerReceiptLineOption(
                  name: 'Extra Cheese',
                  price: Money.parse('70.00'),
                ),
              ],
            ),
            CustomerReceiptLine(
              name: 'Cheese Pizza',
              variantName: 'Large',
              quantity: 1,
              unitPrice: Money.parse('400.00'),
              lineTotal: Money.parse('400.00'),
            ),
            CustomerReceiptLine(
              name: 'French Fries',
              quantity: 2,
              unitPrice: Money.parse('80.00'),
              lineTotal: Money.parse('160.00'),
              options: <CustomerReceiptLineOption>[
                CustomerReceiptLineOption(
                  name: 'Ketchup',
                  price: Money.parse('10.00'),
                  quantity: 2,
                ),
              ],
            ),
          ],
        ),
      );

      expect(paper.hasLineContaining('Cheese Pizza (Medium)'), isTrue);
      expect(paper.hasLineContaining('Cheese Pizza (Large)'), isTrue);
      expect(paper.hasLineContaining('French Fries'), isTrue);
      expect(paper.linesContaining('+ Extra Cheese'), hasLength(1));
      expect(paper.linesContaining('+ Ketchup'), hasLength(1));
      // 320 + 400 + 160
      expect(paper.lineContaining('TOTAL')!.endsWith('880.00'), isTrue);
      expect(paper.hasLineContaining('Items 4'), isTrue);
    });

    test('an item with no size prints without brackets', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name: 'French Fries',
              quantity: 1,
              unitPrice: Money.parse('80.00'),
              lineTotal: Money.parse('80.00'),
            ),
          ],
        ),
      );

      expect(paper.hasLineContaining('French Fries'), isTrue);
      expect(paper.text, isNot(contains('French Fries (')));
    });

    test('a long product name wraps and the paper is never exceeded', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name:
                  'Farmhouse Special Deluxe Paneer Tikka Extra Large Family '
                  'Feast Pizza with Stuffed Crust',
              variantName: 'Large',
              quantity: 2,
              unitPrice: Money.parse('749.50'),
              lineTotal: Money.parse('1499.00'),
              options: <CustomerReceiptLineOption>[
                CustomerReceiptLineOption(
                  name: 'Extra Cheese and Extra Toppings on the whole pizza',
                  price: Money.parse('90.00'),
                  quantity: 2,
                ),
              ],
            ),
          ],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      expect(paper.lineContaining('2 x 749.50')!.endsWith('1499.00'), isTrue);
      expect(paper.lineContaining('TOTAL')!.endsWith('1499.00'), isTrue);
    });

    test('zero discount and zero tax are printed, not omitted', () {
      final EscPosTranscript paper = print(receipt());

      expect(paper.lineContaining('Discount')!.endsWith('0.00'), isTrue);
      expect(paper.lineContaining('Tax')!.endsWith('0.00'), isTrue);
    });

    test('a future discount and tax print in the same block', () {
      // Nothing in this build produces either. When a rate is configured the figures
      // appear with no layout change, which is what this proves.
      final EscPosTranscript paper = print(
        receipt(
          totals: CustomerReceiptTotals(
            subtotal: Money.parse('1000.00'),
            discount: Money.parse('100.00'),
            tax: Money.parse('45.00'),
            total: Money.parse('945.00'),
          ),
        ),
      );

      expect(paper.lineContaining('Subtotal')!.endsWith('1000.00'), isTrue);
      expect(paper.lineContaining('Discount')!.endsWith('100.00'), isTrue);
      expect(paper.lineContaining('Tax')!.endsWith('45.00'), isTrue);
      expect(paper.lineContaining('TOTAL')!.endsWith('945.00'), isTrue);
      expect(paper.widestLine, lessThanOrEqualTo(columns));
    });

    test('rupee amounts are exact to the paisa', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name: 'Odd Priced Item',
              quantity: 3,
              unitPrice: const Money.fromPaise(9999),
              lineTotal: const Money.fromPaise(29997),
            ),
          ],
        ),
      );

      // 99.99 x 3 = 299.97, with no drift, because every figure is integer paise.
      expect(paper.hasLineContaining('3 x 99.99'), isTrue);
      expect(paper.lineContaining('TOTAL')!.endsWith('299.97'), isTrue);
    });

    test('the currency is stated once rather than glyph by glyph', () {
      // The rupee sign has no ESC/POS code page, so the amount columns are digits and
      // the block is labelled instead.
      final EscPosTranscript paper = print(receipt());

      expect(
        paper.hasLineContaining(
          'TOTAL ${EscPosDocumentFormatter.currencyCode}',
        ),
        isTrue,
      );
      expect(paper.text, isNot(contains('\u20B9')));
    });

    test('the payment method and the item count close the bill', () {
      final EscPosTranscript paper = print(
        receipt(paymentMethod: PaymentMethod.upi),
      );

      final String line = paper.lineContaining('Paid by UPI')!;
      expect(line, contains('Items 1'));
    });

    test('an order note is printed under the lines', () {
      expect(
        print(receipt(notes: 'Cut into eight'))
            .hasLineContaining('Note: Cut into eight'),
        isTrue,
      );
    });

    test('the bill ends with a feed and a cut', () {
      final EscPosTranscript paper = print(receipt());

      expect(paper.commands.last, EscPosCommands.cutFull);
      expect(
        paper.commands[paper.commands.length - 2],
        EscPosCommands.feed(PrintProfile.escPos80mm.feedLinesBeforeCut),
      );
    });

    test('a reprint says so, so it cannot pass as a second sale', () {
      expect(
        print(receipt(isReprint: true))
            .hasLineContaining(EscPosDocumentFormatter.reprintMarker),
        isTrue,
      );
      expect(
        print(receipt()).text,
        isNot(contains(EscPosDocumentFormatter.reprintMarker)),
      );
    });

    test('every line of a full bill fits 80mm paper', () {
      final EscPosTranscript paper = print(
        receipt(
          business: const BusinessIdentity(
            name: 'Brisko Pizza Kothrud',
            address: '12 Paud Road, Kothrud, Pune, Maharashtra 411038',
            phone: '02012345678',
            gstin: '27ABCDE1234F1Z5',
            receiptFooter: 'Thank you, please come again',
          ),
          customerPhone: '9876543210',
          notes: 'Extra napkins please, and cut the large one into eight',
          upiPayment: UpiPaymentRequest(
            vpa: 'briskopizza@upi',
            payeeName: 'Brisko Pizza',
            amount: Money.parse('320.00'),
          ),
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      expect(paper.lines, isNotEmpty);
    });
  });

  group('the UPI payment code', () {
    test('the QR carries the payee, the exact amount and the currency', () {
      final UpiPaymentRequest request = UpiPaymentRequest(
        vpa: 'briskopizza@upi',
        payeeName: 'Brisko Pizza',
        amount: Money.parse('640.50'),
        transactionReference: '20260911-0001',
      );

      final EscPosTranscript paper = print(receipt(upiPayment: request));
      final String payload = paper.qrPayloads.single;

      expect(payload, startsWith('upi://pay?'));
      expect(payload, contains('pa=briskopizza%40upi'));
      expect(payload, contains('am=640.50'));
      expect(payload, contains('cu=INR'));
      expect(payload, contains('tr=20260911-0001'));
      expect(paper.hasLineContaining('Scan to pay by UPI'), isTrue);
      expect(paper.hasLineContaining('briskopizza@upi'), isTrue);
    });

    test('a payee name with punctuation is encoded, not broken', () {
      final String payload = UpiPaymentRequest(
        vpa: 'a@b',
        payeeName: 'Brisko Pizza & Co',
        amount: Money.parse('10.00'),
      ).toUri();

      expect(payload, contains('pn=Brisko+Pizza+%26+Co'));
    });

    test('no configured UPI address means no QR at all', () {
      // A QR is a promise that scanning it pays this outlet. There is no honest
      // placeholder for that.
      final EscPosTranscript paper = print(receipt());

      expect(paper.qrPayloads, isEmpty);
      expect(paper.text, isNot(contains('Scan to pay')));
      expect(paper.hasCommand(EscPosCommands.qrPrint), isFalse);
    });

    test('a request is only built once a VPA exists', () {
      expect(
        UpiPaymentRequest.forOrder(
          vpa: null,
          payeeName: 'Brisko Pizza',
          amount: Money.parse('10.00'),
        ),
        isNull,
      );
      expect(
        UpiPaymentRequest.forOrder(
          vpa: '   ',
          payeeName: null,
          amount: Money.parse('10.00'),
        ),
        isNull,
      );

      final UpiPaymentRequest built = UpiPaymentRequest.forOrder(
        vpa: ' briskopizza@upi ',
        payeeName: null,
        amount: Money.parse('10.00'),
        orderNumber: '20260911-0001',
      )!;
      expect(built.vpa, 'briskopizza@upi');
      // Falls back to the address rather than inventing a trading name.
      expect(built.payeeName, 'briskopizza@upi');
      expect(built.transactionNote, 'Order 20260911-0001');
    });
  });

  group('the kitchen slip', () {
    test('it is headed as a kitchen ticket', () {
      final EscPosTranscript paper = print(kot());

      expect(paper.lines.first, 'KITCHEN ORDER TICKET');
      expect(paper.hasCommand(EscPosCommands.sizeDoubleHeight), isTrue);
    });

    test(
      'it carries the slip number, the bill number, the time and the type',
      () {
        final EscPosTranscript paper = print(kot());

        expect(paper.lineContaining('KOT K20260911-0001'), contains('Dine-in'));
        expect(paper.hasLineContaining('Bill 20260911-0001'), isTrue);
        expect(paper.hasLineContaining('11/09/2026'), isTrue);
        // The time is on the slip so the kitchen can see how long an order has waited.
        expect(paper.hasLineContaining(':'), isTrue);
      },
    );

    test('a line shows the size, the options and the quantity', () {
      final EscPosTranscript paper = print(kot());

      expect(paper.hasLineContaining('Cheese Pizza (Medium)'), isTrue);
      expect(paper.hasLineContaining('+ Extra Cheese'), isTrue);
      expect(paper.hasLineContaining('Qty 2'), isTrue);
    });

    test('no price appears anywhere on a kitchen slip', () {
      // The strongest form of this check: the document type has no field to carry an
      // amount, so there is nothing for the formatter to print even by mistake.
      final EscPosTranscript paper = print(
        kot(
          lines: const <KitchenKotLine>[
            KitchenKotLine(
              name: 'Cheese Pizza',
              variantName: 'Large',
              quantity: 1,
              options: <String>['Extra Cheese', 'Thin Crust'],
            ),
            KitchenKotLine(name: 'French Fries', quantity: 2),
          ],
          notes: 'table 4',
        ),
      );

      expect(paper.text, isNot(contains('320')));
      expect(paper.text, isNot(contains('TOTAL')));
      expect(paper.text, isNot(contains('Subtotal')));
      expect(paper.text, isNot(contains('Paid')));
      expect(paper.text, isNot(contains('INR')));
      // No decimal amount of any kind.
      expect(RegExp(r'\d+\.\d{2}').hasMatch(paper.text), isFalse);
    });

    test('multiple lines and options are all listed with their quantities', () {
      final EscPosTranscript paper = print(
        kot(
          lines: const <KitchenKotLine>[
            KitchenKotLine(
              name: 'Cheese Pizza',
              variantName: 'Medium',
              quantity: 2,
              options: <String>['Extra Cheese', 'Thin Crust'],
              notes: 'no onion',
            ),
            KitchenKotLine(
              name: 'Farmhouse',
              variantName: 'Large',
              quantity: 1,
              options: <String>['Cheese Burst'],
            ),
            KitchenKotLine(name: 'French Fries', quantity: 3),
          ],
        ),
      );

      expect(paper.hasLineContaining('Cheese Pizza (Medium)'), isTrue);
      expect(paper.hasLineContaining('Farmhouse (Large)'), isTrue);
      expect(paper.hasLineContaining('French Fries'), isTrue);
      expect(paper.linesContaining('+ Extra Cheese'), hasLength(1));
      expect(paper.linesContaining('+ Thin Crust'), hasLength(1));
      expect(paper.linesContaining('+ Cheese Burst'), hasLength(1));
      expect(paper.hasLineContaining('* no onion'), isTrue);
      expect(paper.linesContaining('Qty 2'), hasLength(1));
      expect(paper.linesContaining('Qty 1'), hasLength(1));
      expect(paper.linesContaining('Qty 3'), hasLength(1));
      // 2 + 1 + 3
      expect(paper.hasLineContaining('Items 6'), isTrue);
    });

    test('an order note is emphasised for the kitchen', () {
      final EscPosTranscript paper = print(kot(notes: 'no onion in anything'));

      expect(paper.hasLineContaining('Note: no onion in anything'), isTrue);
      expect(paper.hasCommand(EscPosCommands.boldOn), isTrue);
    });

    test('a long name wraps inside the paper', () {
      final EscPosTranscript paper = print(
        kot(
          lines: const <KitchenKotLine>[
            KitchenKotLine(
              name:
                  'Farmhouse Special Deluxe Paneer Tikka Extra Large Family '
                  'Feast Pizza with Stuffed Crust',
              variantName: 'Large',
              quantity: 4,
              options: <String>[
                'Extra Cheese and Extra Toppings across the whole pizza',
              ],
            ),
          ],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      expect(paper.hasLineContaining('Qty 4'), isTrue);
    });

    test('the slip ends with a feed and a cut', () {
      final EscPosTranscript paper = print(kot());

      expect(paper.commands.last, EscPosCommands.cutFull);
    });

    test('a reprinted slip says so', () {
      expect(
        print(kot(isReprint: true))
            .hasLineContaining(EscPosDocumentFormatter.reprintMarker),
        isTrue,
      );
    });
  });

  group('the printer test page', () {
    test('the ruler is exactly one line of the paper width', () {
      final EscPosTranscript paper = print(
        PrinterTestPage(printedAt: issuedAt),
      );

      final String ruler = paper.lines.firstWhere(
        (String line) => line.startsWith('1234567890'),
      );
      expect(ruler.length, columns);
      expect(paper.hasLineContaining('Paper'), isTrue);
      expect(paper.hasLineContaining('80mm'), isTrue);
      expect(paper.hasLineContaining('48'), isTrue);
    });

    test('it exercises bold, centring, two columns and the cutter', () {
      final EscPosTranscript paper = print(
        PrinterTestPage(printedAt: issuedAt),
      );

      expect(paper.hasCommand(EscPosCommands.boldOn), isTrue);
      expect(paper.hasCommand(EscPosCommands.alignCentre), isTrue);
      expect(paper.hasCommand(EscPosCommands.sizeDoubleHeight), isTrue);
      expect(paper.hasCommand(EscPosCommands.cutFull), isTrue);
      expect(paper.lineContaining('Two columns')!.length, columns);
    });

    test('a sample QR is printed only when data is supplied', () {
      expect(print(PrinterTestPage(printedAt: issuedAt)).qrPayloads, isEmpty);
      expect(
        print(PrinterTestPage(printedAt: issuedAt, qrData: 'BRISKO-TEST'))
            .qrPayloads,
        <String>['BRISKO-TEST'],
      );
    });
  });

  group('paper budget', () {
    test('a 58mm layout narrows every line', () {
      // Not a supported roll, but proof the width is a value rather than a hard-coded
      // 48 scattered through the formatter.
      const EscPosDocumentFormatter narrow = EscPosDocumentFormatter(
        profile: PrintProfile(paper: PaperWidth.mm58),
      );

      final EscPosTranscript paper = EscPosTranscript.of(
        narrow.encode(receipt()),
      );

      expect(
        paper.widestLine,
        lessThanOrEqualTo(PaperWidth.mm58.characterColumns),
      );
      expect(paper.lineContaining('TOTAL')!.length, 32);
    });
  });

  group('how the bill was paid', () {
    // The method is read off the persisted payment, so each one has to reach the paper
    // as the customer's own record of how they settled.
    test('cash prints Cash', () {
      expect(
        print(receipt(paymentMethod: PaymentMethod.cash))
            .hasLineContaining('Paid by Cash'),
        isTrue,
      );
    });

    test('UPI prints UPI', () {
      expect(
        print(receipt(paymentMethod: PaymentMethod.upi))
            .hasLineContaining('Paid by UPI'),
        isTrue,
      );
    });

    test('card prints Card', () {
      expect(
        print(receipt(paymentMethod: PaymentMethod.card))
            .hasLineContaining('Paid by Card'),
        isTrue,
      );
    });

    test('anything else prints Other rather than guessing', () {
      expect(
        print(receipt(paymentMethod: PaymentMethod.other))
            .hasLineContaining('Paid by Other'),
        isTrue,
      );
    });

    test('only the method that was used appears', () {
      final EscPosTranscript paper = print(
        receipt(paymentMethod: PaymentMethod.card),
      );

      expect(paper.text, isNot(contains('Cash')));
      expect(paper.text, isNot(contains('UPI')));
    });
  });

  group('the kitchen slip carries no counter information', () {
    test('no payment method, no tender and no change', () {
      final EscPosTranscript paper = print(kot(notes: 'table 4'));

      for (final String forbidden in <String>[
        'Paid',
        'Cash',
        'Card',
        'UPI',
        'Change',
        'Subtotal',
        'Discount',
        'Tax',
        'TOTAL',
        'INR',
        'Scan to pay',
        'GSTIN',
      ]) {
        expect(
          paper.text,
          isNot(contains(forbidden)),
          reason: 'A kitchen slip must not mention $forbidden.',
        );
      }
    });

    test('no QR of any kind, so nothing on it can take money', () {
      final EscPosTranscript paper = print(kot());

      expect(paper.qrPayloads, isEmpty);
      expect(paper.hasCommand(EscPosCommands.qrPrint), isFalse);
    });
  });

  group('long text', () {
    const String longOption =
        'Extra Cheese with Extra Jalapenos and Extra Olives across the whole '
        'pizza please';
    const String longNote =
        'Please cut this one into eight pieces and pack the garlic dip on the '
        'side in a separate container, and add two extra paper plates';

    /// The wrapped document read back as one line, so a wrapped phrase can be shown
    /// to have survived in full rather than been cut short.
    String reflow(EscPosTranscript paper) => paper.lines
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .join(' ');

    test('a long option name wraps on a bill and nothing is lost', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name: 'Cheese Pizza',
              variantName: 'Medium',
              quantity: 2,
              unitPrice: Money.parse('320.00'),
              lineTotal: Money.parse('640.00'),
              options: <CustomerReceiptLineOption>[
                CustomerReceiptLineOption(
                  name: longOption,
                  price: Money.parse('90.00'),
                ),
              ],
            ),
          ],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      // Wrapped across lines, and every word of it still there.
      expect(paper.linesContaining('+ $longOption'), isEmpty);
      expect(reflow(paper), contains('+ $longOption'));
      // The arithmetic line is unaffected by the option above it.
      expect(paper.lineContaining('2 x 320.00')!.endsWith('640.00'), isTrue);
    });

    test('a long option name wraps on a kitchen slip too', () {
      final EscPosTranscript paper = print(
        kot(
          lines: const <KitchenKotLine>[
            KitchenKotLine(
              name: 'Cheese Pizza',
              variantName: 'Large',
              quantity: 1,
              options: <String>[longOption, 'Thin Crust'],
            ),
          ],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      expect(reflow(paper), contains('+ $longOption'));
      // The second option is still its own entry rather than being swallowed.
      expect(paper.hasLineContaining('+ Thin Crust'), isTrue);
      expect(paper.hasLineContaining('Qty 1'), isTrue);
    });

    test('a long line note wraps and is not truncated', () {
      final EscPosTranscript paper = print(
        kot(
          lines: const <KitchenKotLine>[
            KitchenKotLine(
              name: 'Cheese Pizza',
              variantName: 'Medium',
              quantity: 1,
              notes: longNote,
            ),
          ],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      // A truncated instruction is a remade pizza, so the whole note survives.
      expect(reflow(paper), contains('* $longNote'));
      expect(paper.text, isNot(contains('..')));
    });

    test('a long order note wraps on both documents', () {
      final EscPosTranscript bill = print(receipt(notes: longNote));
      final EscPosTranscript slip = print(kot(notes: longNote));

      expect(bill.widestLine, lessThanOrEqualTo(columns));
      expect(slip.widestLine, lessThanOrEqualTo(columns));
      expect(reflow(bill), contains('Note: $longNote'));
      expect(reflow(slip), contains('Note: $longNote'));
    });

    test('a long name, a long option and a quantity together still fit', () {
      final EscPosTranscript paper = print(
        receipt(
          lines: <CustomerReceiptLine>[
            CustomerReceiptLine(
              name:
                  'Farmhouse Special Deluxe Paneer Tikka Extra Large Family '
                  'Feast Pizza with Stuffed Crust',
              variantName: 'Extra Large Family Size',
              quantity: 12,
              unitPrice: Money.parse('1249.50'),
              lineTotal: Money.parse('14994.00'),
              options: <CustomerReceiptLineOption>[
                CustomerReceiptLineOption(
                  name: longOption,
                  price: Money.parse('90.00'),
                  quantity: 12,
                ),
              ],
              notes: longNote,
            ),
          ],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      // The amount is at the paper edge, whatever happened above it.
      expect(
        paper.lineContaining('12 x 1249.50')!.endsWith('14994.00'),
        isTrue,
      );
      expect(paper.lineContaining('TOTAL')!.endsWith('14994.00'), isTrue);
    });

    test('an unbroken run of characters is split, not left to the printer', () {
      final EscPosTranscript paper = print(
        kot(
          lines: <KitchenKotLine>[KitchenKotLine(name: 'X' * 120, quantity: 1)],
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
      expect(
        paper.lines
            .where((String line) => line.startsWith('X'))
            .map((String line) => line.length)
            .reduce((int a, int b) => a + b),
        120,
      );
    });

    test('a configured outlet with long details still fits the paper', () {
      final EscPosTranscript paper = print(
        receipt(
          business: const BusinessIdentity(
            name: 'Brisko Pizza Kothrud Extension Branch Number Two',
            address:
                'Shop 12 and 13, Ground Floor, Paud Road, Kothrud, Pune, '
                'Maharashtra 411038, India',
            phone: '02012345678',
            gstin: '27ABCDE1234F1Z5',
            receiptHeader: 'Dine-in, takeaway and delivery, all day every day',
            receiptFooter:
                'Thank you for eating with us, please come again and tell '
                'your friends about the new menu',
          ),
        ),
      );

      expect(paper.widestLine, lessThanOrEqualTo(columns));
    });
  });

  group('deterministic output', () {
    test('the same bill encodes to the same bytes every time', () {
      // Nothing in the layout reads a clock, a random value or a database, which is
      // what makes a retry reproducible and these tests meaningful.
      expect(formatter.encode(receipt()), formatter.encode(receipt()));
      expect(formatter.encode(kot()), formatter.encode(kot()));
    });

    test('a different bill encodes differently', () {
      expect(
        formatter.encode(receipt(paymentMethod: PaymentMethod.card)),
        isNot(formatter.encode(receipt(paymentMethod: PaymentMethod.cash))),
      );
    });
  });

  group('nothing is invented to fill a space', () {
    test('no logo, because no printer has been proved able to print one', () {
      // A bitmap logo needs PrinterCapabilities.supportsGraphics, which stays false
      // until a real device says otherwise. A placeholder image on a customer's bill
      // would be worse than none, so no graphics command is emitted at all.
      expect(PrinterCapabilities.escPos80mm.supportsGraphics, isFalse);

      final List<int> selectors = print(receipt()).commands
          .map((List<int> command) => command[1])
          .toList(growable: false);

      // GS v (raster bit image) and ESC * (bit image) are the two ways a logo would
      // reach the paper.
      expect(selectors, isNot(contains(0x76)));
      expect(selectors, isNot(contains(0x2A)));
    });

    test('an unconfigured outlet prints no empty labels', () {
      final EscPosTranscript paper = print(receipt());

      for (final String absent in <String>[
        'GSTIN',
        'Phone',
        'Address',
        'null',
        'N/A',
        'TBD',
      ]) {
        expect(
          paper.text,
          isNot(contains(absent)),
          reason: 'A blank setting must print nothing, not "$absent".',
        );
      }
    });
  });
}
