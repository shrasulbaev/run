import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<String> installMapFiles(Map<String, dynamic> manifest) async {
  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/maps/${manifest['version']}');
  final marker = File('${root.path}/ready');
  if (!await marker.exists()) {
    for (final entry in manifest['files']) {
      final asset = entry['path'] as String;
      final file = File('${root.path}/$asset');
      await file.parent.create(recursive: true);
      final bytes = await rootBundle.load(asset);
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }
    await marker.writeAsString('ready', flush: true);
  }
  return '${root.uri}';
}
