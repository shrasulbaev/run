import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_model.dart';

class ActivityController extends ChangeNotifier with WidgetsBindingObserver {
  final List<RunRoute> routes;
  final SharedPreferences prefs;
  final String userId;
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
  ActivityController(this.routes, this.prefs, this.userId) {
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
        message = 'Прогресс сохранён. Продолжи с того же места.';
      } catch (_) {
        active = null;
        progress = null;
      }
    }
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
      active = route;
      progress ??= RouteProgress(route);
      progress!.resetContinuity();
      progress!.accept(point, fix.accuracy, fix.timestamp);
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
              final point = GeoPoint(fix.latitude, fix.longitude);
              accuracy = fix.accuracy;
              if (progress!.accept(point, fix.accuracy, fix.timestamp)) {
                location = point;
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
    if (active == null || progress?.complete != true) return;
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
    await discard();
    message = 'Готово! Результат сохранён на этом устройстве.';
    notifyListeners();
  }

  Future<void> discard() async {
    pause();
    active = null;
    progress = null;
    location = null;
    accuracy = null;
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
        }),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
