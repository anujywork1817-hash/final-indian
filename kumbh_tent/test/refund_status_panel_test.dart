import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumbh_tent/features/booking/widgets/refund_status_panel.dart';

/// These render the real widget the Cancellations screen uses.
///
/// The regression they guard: the panel used to be a hardcoded
/// "Processing (5-7 business days)" label shown on every
/// cancelled booking, whether or not a refund existed.
Future<void> pumpPanel(
  WidgetTester tester,
  Map<String, dynamic> booking,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: RefundStatusPanel(booking: booking)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('succeeded refund shows Refunded with the amount', (t) async {
    await pumpPanel(t, {
      'refund_status': 'succeeded',
      'refund_amount': 12345.67,
      'refund_message':
          '₹12345.67 has been refunded to your original '
          'payment method.',
    });

    expect(find.text('Refund Status'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
    expect(find.text('Rs.12345.67'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('pending refund shows Processing', (t) async {
    await pumpPanel(t, {
      'refund_status': 'pending',
      'refund_amount': 500.0,
      'refund_message':
          '₹500.00 will be credited to your original payment '
          'method within 3-4 working days.',
    });

    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Rs.500.00'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
  });

  // A gateway failure is retried automatically, so the customer
  // must not be alarmed with a failure state.
  testWidgets('failed refund still reads as Processing to the user', (t) async {
    await pumpPanel(t, {
      'refund_status': 'failed',
      'refund_amount': 500.0,
      'refund_message':
          '₹500.00 will be credited to your original payment '
          'method within 3-4 working days.',
    });

    expect(find.text('Processing'), findsOneWidget);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('cash refund shows the manual/team state', (t) async {
    await pumpPanel(t, {
      'refund_status': 'manual',
      'refund_amount': 2000.0,
      'refund_message':
          '₹2000.00 will be refunded by our team within '
          '3-4 working days.',
    });

    expect(find.text('Being processed by our team'), findsOneWidget);
    expect(find.byIcon(Icons.support_agent), findsOneWidget);
  });

  testWidgets('not_applicable shows no refund due and hides the amount', (
    t,
  ) async {
    await pumpPanel(t, {
      'refund_status': 'not_applicable',
      'refund_amount': 0.0,
      'refund_message': 'No refund is due for this booking.',
    });

    expect(find.text('No refund due'), findsOneWidget);
    // A zero amount must not be rendered as "Rs.0.00".
    expect(find.textContaining('Rs.'), findsNothing);
  });

  // The critical anti-regression: with no refund record, the UI
  // must NOT promise money.
  testWidgets('missing refund record never promises a refund', (t) async {
    await pumpPanel(t, {'status': 'cancelled'});

    expect(find.text('No refund recorded'), findsOneWidget);
    expect(find.textContaining('5-7'), findsNothing);
    expect(find.textContaining('business days'), findsNothing);
    expect(find.textContaining('working days'), findsNothing);
    expect(find.text('Processing'), findsNothing);
  });

  testWidgets('unknown status falls back safely', (t) async {
    await pumpPanel(t, {'refund_status': 'some_future_status'});

    expect(find.text('No refund recorded'), findsOneWidget);
  });

  testWidgets('integer amounts render with two decimals', (t) async {
    await pumpPanel(t, {'refund_status': 'succeeded', 'refund_amount': 500});

    expect(find.text('Rs.500.00'), findsOneWidget);
  });

  // The approval gate: a cancellation now parks the refund until
  // staff decide, so the UI must show "awaiting", not "coming".
  testWidgets('awaiting_approval reads as pending review', (t) async {
    await pumpPanel(t, {
      'refund_status': 'awaiting_approval',
      'refund_amount': 1500.0,
      'refund_message':
          'Your refund request for ₹1500.00 has been received and is '
          'awaiting approval by our team.',
    });

    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.byIcon(Icons.pending_actions), findsOneWidget);
    // Must not claim the money is already on its way.
    expect(find.text('Processing'), findsNothing);
    expect(find.text('Refunded'), findsNothing);
  });

  testWidgets('rejected shows decline and hides the amount', (t) async {
    await pumpPanel(t, {
      'refund_status': 'rejected',
      'refund_amount': 1500.0,
      'refund_message':
          'Your refund request was declined. Reason: Cancelled after check-in.',
    });

    expect(find.text('Request declined'), findsOneWidget);
    // Showing "Rs.1500.00" on a declined request reads as a
    // promise of money that is not coming.
    expect(find.textContaining('Rs.'), findsNothing);
    expect(find.textContaining('Reason:'), findsOneWidget);
  });

  group('status → visuals mapping', () {
    test('every backend status maps to a distinct, non-empty label', () {
      const statuses = [
        'awaiting_approval',
        'rejected',
        'pending',
        'processing',
        'succeeded',
        'failed',
        'manual',
        'not_applicable',
      ];

      for (final s in statuses) {
        final v = RefundStatusPanel.visualsFor(s);
        expect(v.label, isNotEmpty, reason: '$s has an empty label');
      }

      // pending/processing/failed intentionally share "Processing".
      expect(
        RefundStatusPanel.visualsFor('failed').label,
        RefundStatusPanel.visualsFor('pending').label,
      );
      expect(
        RefundStatusPanel.visualsFor('succeeded').label,
        isNot(RefundStatusPanel.visualsFor('pending').label),
      );
    });

    test('null status is not treated as a promise of money', () {
      final v = RefundStatusPanel.visualsFor(null);
      expect(v.label, 'No refund recorded');
    });
  });
}
