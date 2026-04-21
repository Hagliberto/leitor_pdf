import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leitor_pdf_flutter/app/pdf_reader_app.dart';

void main() {
  testWidgets('Renderiza o app leitor de PDFs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PdfReaderApp(),
      ),
    );

    expect(find.text('Leitor Digital de PDFs'), findsOneWidget);
  });
}
