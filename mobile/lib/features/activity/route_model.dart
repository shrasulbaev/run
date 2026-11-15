import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class GeoPoint {
  final double lat, lon;
  const GeoPoint(this.lat, this.lon);
  List<double> get coordinates => [lon, lat];
  double distance(GeoPoint other) {
    const rad = math.pi / 180;
    final a =
        math.pow(math.sin((other.lat - lat) * rad / 2), 2) +
        math.cos(lat * rad) *
            math.cos(other.lat * rad) *
            math.pow(math.sin((other.lon - lon) * rad / 2), 2);
    return 6371008.8 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class RunRoute {
  final String id, name, mode, description;
  final int distance;
  final List<GeoPoint> points, checkpoints;
  late final samples = resample(points);
  RunRoute.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      mode = j['mode'],
      description = j['description'],
      distance = j['distance_m'],
      points = (j['geometry']['coordinates'] as List)
          .map(
            (p) => GeoPoint((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          )
          .toList(),
      checkpoints = (j['checkpoints'] as List)
          .map(
            (p) => GeoPoint((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          )
          .toList();
  bool get walk => mode == 'walk';
  static Future<List<RunRoute>> load() async => (jsonDecode(
    await rootBundle.loadString('assets/maps/routes.json'),
  ) as List).map((j) => RunRoute.fromJson(j)).toList();
  static List<GeoPoint> resample(List<GeoPoint> points) {
    final result = <GeoPoint>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final segments = math.max(1, (a.distance(b) / 15).ceil());
      for (var j = 1; j <= segments; j++) {
        final f = j / segments;
        result.add(
          GeoPoint(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f),
        );
      }
    }
    return result;
  }
}

class RouteProgress {
  final RunRoute route;
  int index;
  GeoPoint? _last;
  DateTime? _lastTime;
  RouteProgress(this.route, {this.index = 0});
  double get fraction => index / (route.samples.length - 1);
  bool get complete => index >= route.samples.length - 1;
  void resetContinuity() {
    _last = null;
    _lastTime = null;
  }

  /// Only consecutive nearby segments count. A GPS jump cannot fill the drawing.
  bool accept(GeoPoint point, double accuracy, DateTime time) {
    if (!accuracy.isFinite || accuracy > 25 || accuracy < 0) return false;
    if (_lastTime != null) {
      final dt = time.difference(_lastTime!).inMilliseconds / 1000;
      if (dt <= 0) return false;
      final d = _last!.distance(point);
      if (d > 20 && d / dt > (route.walk ? 3.5 : 10)) return false;
      if (dt > 30) {
        resetContinuity();
      }
    }
    if (point.distance(route.samples[index]) > 45) return false;
    _last = point;
    _lastTime = time;
    // A bounded look-ahead follows turns but cannot skip a distant part of a loop.
    final end = math.min(index + 4, route.samples.length - 1);
    for (var candidate = index + 1; candidate <= end; candidate++) {
      if (point.distance(route.samples[candidate]) <= 18) {
        index = candidate;
      } else {
        break;
      }
    }
    return true;
  }
}
