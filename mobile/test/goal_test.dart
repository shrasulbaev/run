import 'dart:async';
import 'dart:convert';

import 'package:adam_run/core/api.dart';
import 'package:adam_run/core/theme.dart';
import 'package:adam_run/features/profile/goal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_test.dart' show MemoryStore, user;

void main() {
  testWidgets(
    'Goal stays open while saving; acknowledged value persists and failure remains editable',
    (tester) async {
      var reply = Completer<http.Response>();
      final store = MemoryStore();
      final api = Api(
        store: store,
        base: 'https://example.com',
        client: MockClient((r) async {
          expect(jsonDecode(r.body)['step_goal'], 12000);
          return reply.future;
        }),
      );
      api.session = {'access_token': 'a', 'refresh_token': 'r', 'user': user};
      Profile? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AdamTheme.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showGoalSheet(context, api, 8000);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('goal-input')), '12000');
      await tester.pump();
      await tester.tap(find.text('Сохранить цель'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Сохраняем…'), findsOneWidget);
      expect(result, isNull);
      reply.complete(
        http.Response(
          '{"detail":"Нет связи"}',
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Нет связи'), findsOneWidget);
      expect(result, isNull);
      reply = Completer<http.Response>();
      await tester.tap(find.text('Сохранить цель'));
      await tester.pump();
      reply.complete(
        http.Response(
          jsonEncode({...user, 'step_goal': 12000}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(result?.goal, 12000);
      expect(jsonDecode(store.value!)['user']['step_goal'], 12000);
    },
  );
  test('Phone auth sends explicit channel and preserves null email', () async {
    final api = Api(
      store: MemoryStore(),
      base: 'https://example.com',
      client: MockClient((r) async {
        expect(jsonDecode(r.body), {
          'identifier': '+996700123456',
          'channel': 'phone',
        });
        return http.Response('{"challenge_id":"phone"}', 200);
      }),
    );
    expect(await api.requestCode('+996700123456', phone: true), 'phone');
    expect(
      Profile.fromJson({...user, 'email': null, 'phone': '+996700123456'})
          .email,
      '',
    );
  });
}
