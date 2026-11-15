import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../activity/route_model.dart';

class RouteMap extends StatefulWidget {
  final RunRoute route;
  final Map<String, dynamic> city;
  final double progress;
  final bool interactive;
  final bool active;
  final GeoPoint? user;
  const RouteMap({
    super.key,
    required this.route,
    required this.city,
    this.progress = 0,
    this.interactive = false,
    this.active = false,
    this.user,
  });
  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  MapLibreMapController? _map;
  bool _loaded = false;
  late String _style;
  @override
  void initState() {
    super.initState();
    _style = makeStyle(widget.city, widget.route, active: widget.active);
  }

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress || old.user != widget.user) _update();
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
              'properties': <String, dynamic>{},
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
          _loaded = true;
          await _fit();
          await _update();
        },
        rotateGesturesEnabled: widget.interactive,
        scrollGesturesEnabled: widget.interactive,
        zoomGesturesEnabled: widget.interactive,
        tiltGesturesEnabled: false,
        compassEnabled: false,
        attributionButtonPosition: AttributionButtonPosition.bottomRight,
        cameraTargetBounds: CameraTargetBounds(
          LatLngBounds(
            southwest: const LatLng(42.861, 74.594),
            northeast: const LatLng(42.887, 74.621),
          ),
        ),
      ),
      if (widget.interactive)
        Positioned(
          right: 10,
          top: 10,
          child: IconButton.filledTonal(
            onPressed: _fit,
            icon: const Icon(Icons.center_focus_strong),
            tooltip: 'Весь маршрут',
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
              '© OpenStreetMap',
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
    'sources': {
      'city': {
        'type': 'geojson',
        'data': city,
        'attribution': '© OpenStreetMap contributors',
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
      {
        'id': 'parks',
        'type': 'fill',
        'source': 'city',
        'filter': [
          '==',
          ['get', 'kind'],
          'park',
        ],
        'paint': {'fill-color': '#172e24', 'fill-outline-color': '#294438'},
      },
      {
        'id': 'roads',
        'type': 'line',
        'source': 'city',
        'filter': [
          '==',
          ['get', 'kind'],
          'road',
        ],
        'paint': {
          'line-color': '#394852',
          'line-width': [
            'match',
            ['get', 'class'],
            ['primary', 'secondary'],
            6,
            ['footway', 'path', 'pedestrian'],
            1.5,
            3,
          ],
        },
      },
      {
        'id': 'road-centers',
        'type': 'line',
        'source': 'city',
        'filter': [
          '==',
          ['get', 'kind'],
          'road',
        ],
        'paint': {
          'line-color': '#1c2931',
          'line-width': [
            'match',
            ['get', 'class'],
            ['primary', 'secondary'],
            4,
            ['footway', 'path', 'pedestrian'],
            .7,
            1.5,
          ],
        },
      },
      {
        'id': 'buildings',
        'type': 'fill-extrusion',
        'source': 'city',
        'filter': [
          '==',
          ['get', 'kind'],
          'building',
        ],
        'paint': {
          'fill-extrusion-color': '#34424b',
          'fill-extrusion-height': 9,
          'fill-extrusion-base': 0,
          'fill-extrusion-opacity': .8,
        },
      },
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
        'type': 'circle',
        'source': 'user',
        'paint': {
          'circle-radius': 5,
          'circle-color': '#bbecff',
          'circle-stroke-color': '#3987bc',
          'circle-stroke-width': 2,
        },
      },
    ],
  });
}
