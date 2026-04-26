import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lib/app/pdf_reader_app.dart';

void main() {
  testWidgets('Renderiza o app leitor de PDFs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: PdfReaderApp(),
      ),
    );

    expect(find.text('Leitor Digital de PDFs'), findsOneWidget);
  });
}
