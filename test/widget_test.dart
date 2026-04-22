import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('Renders the PDF reader app', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Digital PDF Reader'),
          ),
        ),
      ),
    );

    expect(find.text('Digital PDF Reader'), findsOneWidget);
  });
}
