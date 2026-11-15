import 'package:adam_run/features/activity/route_model.dart';
import 'package:adam_run/features/steps/step_service.dart';
import 'package:flutter_test/flutter_test.dart';

RunRoute route() => RunRoute.fromJson({
  'id': 'test',
  'name': 'Test',
  'mode': 'walk',
  'description': '',
  'distance_m': 220,
  'geometry': {
    'coordinates': [
      [74.60, 42.87],
      [74.60, 42.872],
    ],
  },
  'checkpoints': [
    [74.60, 42.87],
    [74.60, 42.872],
  ],
});

void main() {
  test('Poor accuracy and jumps cannot draw unwalked route', () {
    final r = route(), p = RouteProgress(route());
    final now = DateTime(2026, 11, 16);
    expect(p.accept(r.points.first, 100, now), false);
    expect(p.fraction, 0);
    expect(p.accept(r.points.first, 5, now), true);
    final before = p.index;
    expect(
      p.accept(r.points.last, 5, now.add(const Duration(seconds: 2))),
      false,
    );
    expect(p.index, before);
    expect(p.complete, false);
  });
  test('Consecutive walking completes the route and repeat fixes cannot add distance', () {
    final r = route(), p = RouteProgress(route());
    final now = DateTime(2026, 11, 16);
    for (var i = 0; i < r.samples.length; i++) {
      p.accept(r.samples[i], 5, now.add(Duration(seconds: i * 12)));
    }
    expect(p.complete, true);
    expect(p.fraction, 1);
    p.accept(r.samples.last, 5, now.add(const Duration(hours: 1)));
    expect(p.fraction, 1);
  });
  test('Resume retains ordered progress; old timestamps ignored', () {
    final r = route(), p = RouteProgress(route(), index: 5);
    final now = DateTime(2026, 11, 16);
    expect(p.accept(r.samples.first, 5, now), false);
    p.accept(r.samples[5], 5, now);
    final saved = p.index;
    p.accept(r.samples[6], 5, now.subtract(const Duration(seconds: 1)));
    expect(p.index, saved);
  });
  test('Daily streak does not break until today is over; never invent missing history', () {
    const s = StepSnapshot(
      history: {
        '2026-11-16': 100,
        '2026-11-15': 8000,
        '2026-11-14': 9000,
        '2026-11-13': 100,
      },
    );
    expect(s.streak(8000, DateTime(2026, 11, 16)), 2);
    expect(s.streak(10000, DateTime(2026, 11, 16)), 0);
    expect(const StepSnapshot(status: 'unsupported').count, isNull);
  });
  test('Bundled routes are closed, distinct and unbranded', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final routes = await RunRoute.load();
    expect(routes.length, 2);
    expect(routes.map((r) => r.mode).toSet(), {'walk', 'run'});
    for (final r in routes) {
      expect(r.points.first.distance(r.points.last), lessThan(1));
      expect(r.name.contains('Бублик'), false);
      expect(r.distance, greaterThan(1000));
    }
  });
}
