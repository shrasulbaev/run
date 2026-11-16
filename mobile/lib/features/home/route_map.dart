import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../activity/route_model.dart';

class RouteMap extends StatefulWidget {
  final RunRoute route;
  final Map<String, dynamic> city;
  final double progress;
  final bool interactive;
  final bool active;
  final bool running;
  final double heading;
  final GeoPoint? user;
  const RouteMap({
    super.key,
    required this.route,
    required this.city,
    this.progress = 0,
    this.interactive = true,
    this.active = false,
    this.running = false,
    this.heading = 0,
    this.user,
  });
  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  MapLibreMapController? _map;
  bool _loaded = false;
  Timer? _pulse;
  double _phase = 0;
  late String _style;
  @override
  void initState() {
    super.initState();
    _style = makeStyle(widget.city, widget.route, active: widget.active);
    _pulse = Timer.periodic(const Duration(milliseconds: 160), (_) async {
      if (!_loaded || !widget.running || _map == null) return;
      _phase = (_phase + .12) % 1;
      try {
        await _map!.setLayerProperties(
          'user-glow',
          CircleLayerProperties(
            circleRadius: 12 + _phase * 16,
            circleOpacity: (1 - _phase) * .4,
          ),
        );
      } catch (_) {}
    });
  }

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress ||
        old.user != widget.user ||
        old.running != widget.running ||
        old.heading != widget.heading) {
      _update();
    }
  }

  Map<String, dynamic> _line(List<GeoPoint> points) => {
    'type': 'Feature',
    'properties': <String, dynamic>{},
    'geometry': {
      'type': 'LineString',
      'coordinates': points.map((p) => p.coordinates).toList(),
    },
  };
  Future<void> _update() async {
    if (!_loaded || _map == null) return;
    final samples = widget.route.samples;
    final end = (widget.progress * (samples.length - 1)).floor().clamp(
      0,
      samples.length - 1,
    );
    final points = end > 0
        ? samples.take(end + 1).toList()
        : [samples.first, samples.first];
    try {
      await _map!.setGeoJsonSource('progress', _line(points));
      await _map!.setGeoJsonSource('user', {
        'type': 'FeatureCollection',
        'features': [
          if (widget.user != null)
            {
              'type': 'Feature',
              'properties': <String, dynamic>{
                'running': widget.running,
                'heading': widget.heading,
              },
              'geometry': {
                'type': 'Point',
                'coordinates': widget.user!.coordinates,
              },
            },
        ],
      });
    } catch (_) {
      /* A route switch can dispose a native map while updating. */
    }
  }

  Future<void> _fit() async {
    if (!mounted || !_loaded || _map == null) return;
    try {
      final p = widget.route.points;
      await _map?.moveCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              p.map((p) => p.lat).reduce(math.min),
              p.map((p) => p.lon).reduce(math.min),
            ),
            northeast: LatLng(
              p.map((p) => p.lat).reduce(math.max),
              p.map((p) => p.lon).reduce(math.max),
            ),
          ),
          left: 35,
          right: 35,
          top: 35,
          bottom: 35,
        ),
      );
    } on PlatformException catch (e) {
      if (e.code != 'MAP_NOT_READY') rethrow;
    }
  }

  @override
  void dispose() {
    _pulse?.cancel();
    _loaded = false;
    _map = null;
    super.dispose();
  }

  Future<void> _arrow() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final path = Path()
      ..moveTo(32, 3)
      ..lineTo(55, 58)
      ..lineTo(32, 46)
      ..lineTo(9, 58)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = AdamTheme.orange);
    final picture = recorder.endRecording();
    final bitmap = await picture.toImage(64, 64);
    final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    if (data != null && mounted) {
      await _map?.addImage('direction-arrow', data.buffer.asUint8List());
    }
    bitmap.dispose();
    picture.dispose();
  }

  Future<void> _zoom(double amount) async {
    final camera = await _map?.queryCameraPosition();
    if (camera != null) {
      await _map?.animateCamera(
        CameraUpdate.zoomTo((camera.zoom + amount).clamp(8, 20)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      MapLibreMap(
        annotationOrder: const [],
        styleString: _style,
        initialCameraPosition: CameraPosition(
          target: LatLng(
            widget.route.points.first.lat,
            widget.route.points.first.lon,
          ),
          zoom: 14.7,
        ),
        onMapCreated: (m) => _map = m,
        onStyleLoadedCallback: () async {
          if (!mounted) return;
          _loaded = true;
          try {
            await _arrow();
            await _fit();
            await _update();
          } on PlatformException catch (e) {
            if (e.code != 'MAP_NOT_READY') rethrow;
          }
        },
        gestureRecognizers: widget.interactive
            ? {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              }
            : {},
        minMaxZoomPreference: const MinMaxZoomPreference(8, 20),
        rotateGesturesEnabled: widget.interactive,
        scrollGesturesEnabled: widget.interactive,
        zoomGesturesEnabled: widget.interactive,
        tiltGesturesEnabled: false,
        compassEnabled: false,
        attributionButtonPosition: AttributionButtonPosition.bottomRight,
      ),
      if (widget.interactive)
        Positioned(
          right: 10,
          top: 10,
          child: Column(
            children: [
              IconButton.filledTonal(
                onPressed: _fit,
                icon: const Icon(Icons.route),
                tooltip: 'Весь маршрут',
              ),
              const SizedBox(height: 4),
              IconButton.filledTonal(
                onPressed: () => _zoom(1),
                icon: const Icon(Icons.add),
                tooltip: 'Приблизить',
              ),
              const SizedBox(height: 4),
              IconButton.filledTonal(
                onPressed: () => _zoom(-1),
                icon: const Icon(Icons.remove),
                tooltip: 'Отдалить',
              ),
              if (widget.user != null) ...[
                const SizedBox(height: 4),
                IconButton.filledTonal(
                  onPressed: () => _map?.animateCamera(
                    CameraUpdate.newLatLng(
                      LatLng(widget.user!.lat, widget.user!.lon),
                    ),
                  ),
                  icon: const Icon(Icons.my_location),
                  tooltip: 'Моя позиция',
                ),
              ],
            ],
          ),
        ),
      Positioned(
        left: 10,
        bottom: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AdamTheme.background.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              'Офлайн · © OpenStreetMap / OpenMapTiles',
              style: TextStyle(fontSize: 10, color: AdamTheme.muted),
            ),
          ),
        ),
      ),
    ],
  );
}

String makeStyle(
  Map<String, dynamic> city,
  RunRoute route, {
  bool active = false,
}) {
  Map<String, dynamic> line(List<GeoPoint> p) => {
    'type': 'Feature',
    'properties': <String, dynamic>{},
    'geometry': {
      'type': 'LineString',
      'coordinates': p.map((p) => p.coordinates).toList(),
    },
  };
  return jsonEncode({
    'version': 8,
    'name': 'ADAM RUN Night',
    if (city['glyphs'] != null) 'glyphs': city['glyphs'],
    'sources': {
      'city': {
        if (city['type'] == 'vector')
          ...Map<String, dynamic>.from(city)..remove('glyphs')
        else ...{
          'type': 'geojson',
          'data': city,
          'attribution': '© OpenStreetMap contributors',
        },
      },
      'route': {'type': 'geojson', 'data': line(route.points)},
      'progress': {
        'type': 'geojson',
        'data': line([route.points.first, route.points.first]),
      },
      'points': {
        'type': 'geojson',
        'data': {
          'type': 'FeatureCollection',
          'features': route.checkpoints
              .map(
                (p) => {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {'type': 'Point', 'coordinates': p.coordinates},
                },
              )
              .toList(),
        },
      },
      'start': {
        'type': 'geojson',
        'data': {
          'type': 'Point',
          'coordinates': route.points.first.coordinates,
        },
      },
      'user': {
        'type': 'geojson',
        'data': {'type': 'FeatureCollection', 'features': []},
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#0c1319'},
      },
      if (city['type'] == 'vector') ...[
        {
          'id': 'landcover',
          'type': 'fill',
          'source': 'city',
          'source-layer': 'landcover',
          'paint': {'fill-color': '#17291f', 'fill-opacity': .65},
        },
        {
          'id': 'parks',
          'type': 'fill',
          'source': 'city',
          'source-layer': 'park',
          'paint': {'fill-color': '#1b3327', 'fill-outline-color': '#294736'},
        },
        {
          'id': 'water',
          'type': 'fill',
          'source': 'city',
          'source-layer': 'water',
          'paint': {'fill-color': '#163641'},
        },
        {
          'id': 'roads',
          'type': 'line',
          'source': 'city',
          'source-layer': 'transportation',
          'paint': {
            'line-color': '#40505a',
            'line-width': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10,
              .8,
              16,
              5,
              19,
              12,
            ],
          },
        },
        {
          'id': 'road-centers',
          'type': 'line',
          'source': 'city',
          'source-layer': 'transportation',
          'paint': {
            'line-color': '#22313b',
            'line-width': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10,
              .4,
              16,
              3,
              19,
              8,
            ],
          },
        },
        {
          'id': 'paths',
          'type': 'line',
          'source': 'city',
          'source-layer': 'transportation',
          'filter': [
            '==',
            ['get', 'class'],
            'path',
          ],
          'paint': {
            'line-color': '#8b9694',
            'line-width': 1,
            'line-dasharray': [2, 2],
          },
        },
        {
          'id': 'buildings',
          'type': 'fill',
          'source': 'city',
          'source-layer': 'building',
          'minzoom': 14,
          'paint': {'fill-color': '#2b3a44', 'fill-outline-color': '#3b4b56'},
        },
        {
          'id': 'street-labels',
          'type': 'symbol',
          'source': 'city',
          'source-layer': 'transportation_name',
          'minzoom': 13,
          'layout': {
            'symbol-placement': 'line',
            'text-field': [
              'coalesce',
              ['get', 'name:ru'],
              ['get', 'name'],
              '',
            ],
            'text-font': ['Noto Sans Regular'],
            'text-size': 11,
            'text-max-angle': 30,
          },
          'paint': {
            'text-color': '#b5c1c8',
            'text-halo-color': '#10191f',
            'text-halo-width': 2,
          },
        },
        {
          'id': 'place-labels',
          'type': 'symbol',
          'source': 'city',
          'source-layer': 'place',
          'maxzoom': 14,
          'layout': {
            'text-field': [
              'coalesce',
              ['get', 'name:ru'],
              ['get', 'name'],
              '',
            ],
            'text-font': ['Noto Sans Regular'],
            'text-size': 14,
          },
          'paint': {
            'text-color': '#c0ced3',
            'text-halo-color': '#10191f',
            'text-halo-width': 2,
          },
        },
      ],
      {
        'id': 'route-shadow',
        'type': 'line',
        'source': 'route',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {'line-color': '#000000', 'line-width': 9},
      },
      {
        'id': 'route-glow',
        'type': 'line',
        'source': 'route',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {
          'line-color': '#ff771f',
          'line-width': 13,
          'line-blur': 9,
          'line-opacity': active ? .06 : .55,
        },
      },
      {
        'id': 'route-line',
        'type': 'line',
        'source': 'route',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {
          'line-color': active ? '#8596a2' : '#ff8e3d',
          'line-width': 3,
          if (active) 'line-dasharray': [2, 2],
        },
      },
      {
        'id': 'progress-line',
        'type': 'line',
        'source': 'progress',
        'layout': {'line-join': 'round', 'line-cap': 'round'},
        'paint': {'line-color': '#ff8d30', 'line-width': 5},
      },
      {
        'id': 'checkpoints',
        'type': 'circle',
        'source': 'points',
        'paint': {
          'circle-radius': 4,
          'circle-color': '#192229',
          'circle-stroke-color': '#ffb76c',
          'circle-stroke-width': 2,
        },
      },
      {
        'id': 'start-marker',
        'type': 'circle',
        'source': 'start',
        'paint': {
          'circle-radius': 8,
          'circle-color': '#ff7a20',
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 2,
        },
      },
      {
        'id': 'user-glow',
        'type': 'circle',
        'source': 'user',
        'paint': {
          'circle-radius': 14,
          'circle-color': '#62bfff',
          'circle-opacity': .2,
        },
      },
      {
        'id': 'user-point',
        'filter': [
          '!=',
          ['get', 'running'],
          true,
        ],
        'type': 'circle',
        'source': 'user',
        'paint': {
          'circle-radius': 5,
          'circle-color': '#bbecff',
          'circle-stroke-color': '#3987bc',
          'circle-stroke-width': 2,
        },
      },
      {
        'id': 'user-arrow',
        'type': 'symbol',
        'source': 'user',
        'filter': [
          '==',
          ['get', 'running'],
          true,
        ],
        'layout': {
          'icon-image': 'direction-arrow',
          'icon-size': .5,
          'icon-rotate': ['get', 'heading'],
          'icon-rotation-alignment': 'map',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
    ],
  });
}
