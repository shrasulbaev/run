import 'package:adam_run/core/api.dart';
import 'package:adam_run/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native registration, secure session, steps bridge, goal and modes',
    (tester) async {
      await SecureTokenStore().clear();
      await app.main();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'QA Runner');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'native${DateTime.now().microsecondsSinceEpoch}@example.com',
      );
      await tester.ensureVisible(find.text('Получить код'));
      await tester.tap(find.text('Получить код'));
      for (
        var i = 0;
        i < 30 && find.byKey(const Key('otp')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('otp')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('otp')), '00000');
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      for (
        var i = 0;
        i < 40 && find.text('Walk Quest').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Walk Quest'), findsOneWidget);
      expect(await SecureTokenStore().read(), isNotNull);
      final steps = await const MethodChannel('kg.adamrun/steps')
          .invokeMapMethod<String, dynamic>('snapshot', {'request': false});
      expect(
        steps?['status'],
        isIn(['ready', 'permissionRequired', 'denied', 'unsupported']),
      );
      await tester.tap(find.byKey(const Key('daily-goal')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10000');
      await tester.tap(find.text('Сохранить цель'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      final api = Api();
      expect((await api.restore())?.goal, 10000);
      await tester.ensureVisible(find.text('Run Race'));
      await tester.tap(find.text('Run Race'));
      await tester.pumpAndSettle();
      expect(find.text('Парковый Sprint'), findsOneWidget);
      await tester.tap(find.text('Walk Quest'));
      await tester.pumpAndSettle();
      expect(find.text('Городская птица'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
