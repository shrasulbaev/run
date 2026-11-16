import 'dart:async';
import 'dart:convert';

import 'package:adam_run/core/api.dart';
import 'package:adam_run/features/activity/activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_test.dart' show MemoryStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Rejected GPS proof does not block subsequent results', () async {
    SharedPreferences.setMockInitialValues({
      'pending.u': jsonEncode([
        {'id': 'bad'},
        {'id': 'good'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final api = Api(
      store: MemoryStore(),
      base: 'https://example.com',
      client: MockClient((r) async {
        calls++;
        return http.Response(
          calls == 1 ? '{"detail":"invalid trace"}' : '{}',
          calls == 1 ? 422 : 200,
        );
      }),
    );
    api.session = {'access_token': 'a'};
    final controller = ActivityController([], prefs, 'u', api: api);
    addTearDown(controller.dispose);
    for (var i = 0; i < 30 && calls < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(jsonDecode(prefs.getString('pending.u')!), isEmpty);
    expect(jsonDecode(prefs.getString('rejected.u')!).single['id'], 'bad');
  });
  test('A completed upload cannot erase a newly queued activity', () async {
    SharedPreferences.setMockInitialValues({'pending.u': '[{"id":"first"}]'});
    final prefs = await SharedPreferences.getInstance();
    final reply = Completer<http.Response>();
    final api = Api(
      store: MemoryStore(),
      base: 'https://example.com',
      client: MockClient((_) => reply.future),
    );
    api.session = {'access_token': 'a'};
    final controller = ActivityController([], prefs, 'u', api: api);
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await prefs.setString('pending.u', '[{"id":"first"},{"id":"second"}]');
    reply.complete(http.Response('{}', 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(jsonDecode(prefs.getString('pending.u')!).single['id'], 'second');
  });
}
