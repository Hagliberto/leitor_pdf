import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folhear/app/pdf_reader_app.dart';

void main() {
  testWidgets('Renderiza o aplicativo Folhear', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PdfReaderApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Folhear'), findsWidgets);
  });
}
