import 'dart:convert';

import 'package:adam_run/core/api.dart';
import 'package:adam_run/core/theme.dart';
import 'package:adam_run/features/auth/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

http.Response response(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

final user = {
  'id': 'one',
  'email': 'runner@example.com',
  'nickname': 'Адам',
  'step_goal': 8000,
};
void main() {
  testWidgets(
    'Registration requires email/name; only verified server response opens home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Profile? signedIn;
      final api = Api(
        store: MemoryStore(),
        base: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path.endsWith('request-code')) {
            return response('{"challenge_id":"c"}', 200);
          }
          final data = jsonDecode(r.body);
          if (data['code'] != '00000') {
            return response(
              '{"detail":"Неверный код"}',
              400,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return response(
            jsonEncode({
              'access_token': 'access',
              'refresh_token': 'refresh',
              'user': user,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdamTheme.theme,
          home: AuthScreen(api: api, onSignedIn: (u) => signedIn = u),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Адам');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'runner@example.com',
      );
      await tester.ensureVisible(find.text('Получить код'));
      await tester.tap(find.text('Получить код'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('otp')), '12345');
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(signedIn, isNull);
      expect(find.text('Неверный код'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('otp')), '00000');
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(signedIn?.id, 'one');
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Expired access refreshes once, rotates credentials and persists them',
    () async {
      final store = MemoryStore();
      store.value = jsonEncode({
        'access_token': 'expired',
        'refresh_token': 'old-refresh-token-12345678',
        'user': user,
      });
      var refreshes = 0;
      final api = Api(
        store: store,
        base: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/auth/refresh') {
            refreshes++;
            return response(
              jsonEncode({
                'access_token': 'new',
                'refresh_token': 'rotated',
                'user': user,
              }),
              200,
            );
          }
          return r.headers['Authorization'] == 'Bearer new'
              ? response(jsonEncode(user), 200)
              : response('{"detail":"expired"}', 401);
        }),
      );
      expect((await api.restore())?.id, 'one');
      expect(refreshes, 1);
      expect(jsonDecode(store.value!)['refresh_token'], 'rotated');
    },
  );
}
