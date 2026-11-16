import 'dart:convert';

import 'package:flutter/services.dart';

import 'offline_files_stub.dart' if (dart.library.io) 'offline_files_io.dart';

class OfflineMap {
  static Future<Map<String, dynamic>> load() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/maps/offline_manifest.json'),
    ) as Map<String, dynamic>;
    final base = await installMapFiles(manifest);
    return {
      'type': 'vector',
      'tiles': ['${base}assets/maps/offline/{z}/{x}/{y}.pbf'],
      'minzoom': manifest['minzoom'],
      'maxzoom': manifest['maxzoom'],
      'bounds': manifest['bounds'],
      'attribution': manifest['attribution'],
      'glyphs': '${base}assets/maps/offline/fonts/{fontstack}/{range}.pbf',
    };
  }
}
