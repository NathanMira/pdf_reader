import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/main.dart';
import 'package:pdf_reader/services/library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('文库首页展示打开入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LibraryStore(prefs);

    await tester.pumpWidget(PdfReaderApp(store: store));

    expect(find.text('PDF阅读'), findsOneWidget);
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.text('打开链接'), findsOneWidget);
    expect(find.text('还没有阅读记录'), findsOneWidget);
  });
}
