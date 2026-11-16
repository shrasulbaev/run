import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../core/api.dart';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_model.dart';

class ActivityController extends ChangeNotifier with WidgetsBindingObserver {
  final List<RunRoute> routes;
  final SharedPreferences prefs;
  final String userId;
  final Api? api;
  double heading = 0;
  String? attemptId;
  DateTime? startedAt;
  List<Map<String, dynamic>> _trace = [];
  bool _syncing = false;
  String? syncMessage;
  String _uuid() {
    final r = math.Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  void _record(Position fix) {
    if (_trace.isNotEmpty &&
        fix.timestamp.millisecondsSinceEpoch <= _trace.last['time_ms']) {
      return;
    }
    if (_trace.length >= 5000) {
      message =
          'Слишком длинная запись. Рейтинг для этого прохождения недоступен.';
      attemptId = null;
      return;
    }
    if (fix.heading.isFinite && fix.heading >= 0 && fix.speed > .5) {
      heading = fix.heading;
    } else if (active != null && progress != null) {
      final target = active!
          .samples[math.min(progress!.index + 1, active!.samples.length - 1)];
      final lat = fix.latitude * math.pi / 180,
          other = target.lat * math.pi / 180,
          delta = (target.lon - fix.longitude) * math.pi / 180;
      heading =
          (math.atan2(
                    math.sin(delta) * math.cos(other),
                    math.cos(lat) * math.sin(other) -
                        math.sin(lat) * math.cos(other) * math.cos(delta),
                  ) *
                  180 /
                  math.pi +
              360) %
          360;
    }
    _trace.add({
      'lat': fix.latitude,
      'lon': fix.longitude,
      'accuracy': fix.accuracy,
      'time_ms': fix.timestamp.millisecondsSinceEpoch,
      'mocked': fix.isMocked,
    });
  }

  Future<void> sync() async {
    if (api == null || _syncing) return;
    _syncing = true;
    try {
      final pending =
          (jsonDecode(prefs.getString('pending.$userId') ?? '[]') as List);
      for (final entry in pending.toList()) {
        try {
          await api!.postData('/activities', Map<String, dynamic>.from(entry));
          final latest =
              jsonDecode(prefs.getString('pending.$userId') ?? '[]') as List;
          latest.removeWhere((p) => p['id'] == entry['id']);
          await prefs.setString('pending.$userId', jsonEncode(latest));
          syncMessage =
              'Результат синхронизирован. Профиль и рейтинг обновлены.';
        } on ApiException catch (e) {
          if (e.status == 422 || e.status == 409) {
            final rejected =
                jsonDecode(prefs.getString('rejected.$userId') ?? '[]') as List;
            rejected.add({...entry, 'error': e.message});
            await prefs.setString('rejected.$userId', jsonEncode(rejected));
            final latest =
                jsonDecode(prefs.getString('pending.$userId') ?? '[]') as List;
            latest.removeWhere((p) => p['id'] == entry['id']);
            await prefs.setString('pending.$userId', jsonEncode(latest));
            syncMessage =
                'Сервер не принял результат: ${e.message}. Он остался в личной истории.';
            continue;
          }
          syncMessage =
              'Результат сохранён на телефоне. Отправим при подключении.';
          break;
        }
      }
    } finally {
      _syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  RunRoute? active;
  RouteProgress? progress;
  bool running = false, busy = false, _disposed = false;
  String? message;
  GeoPoint? location;
  double? accuracy;
  final Stopwatch _clock = Stopwatch();
  int _savedMillis = 0;
  Timer? _ticker;
  StreamSubscription<Position>? _positions;
  ActivityController(this.routes, this.prefs, this.userId, {this.api}) {
    WidgetsBinding.instance.addObserver(this);
    final raw = prefs.getString('activity.$userId');
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        active = routes.firstWhere((r) => r.id == j['route']);
        progress = RouteProgress(
          active!,
          index: (j['index'] as int).clamp(0, active!.samples.length - 1),
        );
        _savedMillis = j['elapsed'];
        attemptId = j['attempt_id'];
        startedAt = DateTime.tryParse(j['started_at'] ?? '');
        _trace = (j['trace'] as List? ?? [])
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        message = 'Прогресс сохранён. Продолжи с того же места.';
      } catch (_) {
        active = null;
        progress = null;
      }
    }
    unawaited(sync());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (running) {
        notifyListeners();
        if (elapsed.inSeconds % 10 == 0) _persist();
      }
    });
  }
  Duration get elapsed =>
      Duration(milliseconds: _savedMillis + _clock.elapsedMilliseconds);
  double get fraction => progress?.fraction ?? 0;
  int get xp => prefs.getBool('drawing.$userId.city-bird') == true ? 200 : 0;
  bool get collected => xp > 0;
  int? best(String id) => prefs.getInt('best.$userId.$id');
  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Включи геолокацию в настройках телефона.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Для прохождения нужен доступ к точной геолокации.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> start(RunRoute route) async {
    if (busy || running) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final fix = await _position();
      if (_disposed) return;
      final point = GeoPoint(fix.latitude, fix.longitude);
      location = point;
      accuracy = fix.accuracy;
      if (fix.accuracy > 25) {
        throw Exception(
          'GPS пока неточный (±${fix.accuracy.round()} м). Выйди на открытое место.',
        );
      }
      final target = active?.id == route.id
          ? route.samples[progress!.index]
          : route.points.first;
      final distance = point.distance(target);
      if (distance > 45) {
        throw Exception(
          'До ${active == null ? 'старта' : 'места продолжения'} ${distance.round()} м. Подойди к отмеченной точке на карте.',
        );
      }
      if (active == null || active!.id != route.id) {
        startedAt = fix.timestamp;
        _trace = [];
        attemptId = null;
        if (api != null) {
          message = 'Подтверждаем старт…';
          notifyListeners();
          try {
            final ticket = await api!
                .postData('/attempts', {'route_id': route.id})
                .timeout(const Duration(seconds: 12));
            attemptId = ticket['id'];
          } catch (_) {
            message = 'Старт без сети: это прохождение сохранится как личный результат.';
          }
        }
        if (_disposed) return;
        progress = RouteProgress(route);
      }
      active = route;
      progress ??= RouteProgress(route);
      progress!.resetContinuity();
      if (progress!.accept(point, fix.accuracy, fix.timestamp)) _record(fix);
      running = true;
      _clock.start();
      _positions =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 3,
            ),
          ).listen(
            (fix) {
              if (!running) return;
              if (_trace.isNotEmpty &&
                  fix.timestamp.millisecondsSinceEpoch <=
                      _trace.last['time_ms']) {
                return;
              }
              final point = GeoPoint(fix.latitude, fix.longitude);
              accuracy = fix.accuracy;
              if (progress!.accept(point, fix.accuracy, fix.timestamp)) {
                location = point;
                _record(fix);
                message = null;
                _persist();
              } else {
                message = fix.accuracy > 25
                    ? 'GPS неточный — участок пока не засчитан.'
                    : 'Вернись к непройденному участку маршрута.';
              }
              notifyListeners();
            },
            onError: (_) {
              pause();
              message = 'GPS недоступен. Прогресс сохранён.';
              notifyListeners();
            },
          );
      _persist();
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void pause() {
    running = false;
    _clock.stop();
    _positions?.cancel();
    _positions = null;
    progress?.resetContinuity();
    _persist();
    if (!_disposed) notifyListeners();
  }

  Future<void> finish() async {
    if (busy || active == null || progress?.complete != true) return;
    busy = true;
    pause();
    if (active!.walk) {
      await prefs.setBool('drawing.$userId.${active!.id}', true);
    } else {
      final old = best(active!.id);
      if (old == null || elapsed.inMilliseconds < old) {
        await prefs.setInt(
          'best.$userId.${active!.id}',
          elapsed.inMilliseconds,
        );
      }
    }
    final finishedId = _uuid();
    final local =
        jsonDecode(prefs.getString('local_history.$userId') ?? '[]') as List;
    local.insert(0, {
      'id': finishedId,
      'route_id': active!.id,
      'route_name': active!.name,
      'mode': active!.mode,
      'elapsed_ms': elapsed.inMilliseconds,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    });
    await prefs.setString(
      'local_history.$userId',
      jsonEncode(local.take(100).toList()),
    );
    if (api != null && _trace.length >= 10 && startedAt != null) {
      final pending =
          jsonDecode(prefs.getString('pending.$userId') ?? '[]') as List;
      pending.add({
        'id': finishedId,
        'route_id': active!.id,
        'attempt_id': attemptId,
        'elapsed_ms': DateTime.now()
            .difference(startedAt ?? DateTime.now())
            .inMilliseconds,
        'moving_ms': elapsed.inMilliseconds,
        'trace': _trace,
      });
      await prefs.setString('pending.$userId', jsonEncode(pending));
    }
    await discard();
    busy = false;
    message = 'Готово! Результат сохранён. Отправляем в профиль…';
    unawaited(sync());
    notifyListeners();
  }

  Future<void> discard() async {
    pause();
    active = null;
    progress = null;
    location = null;
    accuracy = null;
    attemptId = null;
    startedAt = null;
    _trace = [];
    _clock.reset();
    _savedMillis = 0;
    message = null;
    await prefs.remove('activity.$userId');
    if (!_disposed) notifyListeners();
  }

  void _persist() {
    if (active != null) {
      prefs.setString(
        'activity.$userId',
        jsonEncode({
          'route': active!.id,
          'index': progress!.index,
          'elapsed': elapsed.inMilliseconds,
          'attempt_id': attemptId,
          'started_at': startedAt?.toIso8601String(),
          'trace': _trace,
        }),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (running) {
        pause();
        message = 'Запись маршрута на паузе, пока приложение свёрнуто.';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
