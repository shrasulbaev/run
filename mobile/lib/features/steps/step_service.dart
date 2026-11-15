import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class StepSnapshot {
  final int? count;
  final String status, source, day;
  final bool partial;
  final Map<String, int> history;
  const StepSnapshot({
    this.count,
    this.status = 'permissionRequired',
    this.source = '',
    this.day = '',
    this.partial = false,
    this.history = const {},
  });
  factory StepSnapshot.fromMap(Map data) => StepSnapshot(
    count: data['count'] as int?,
    status: data['status'] ?? 'error',
    source: data['source'] ?? '',
    day: data['day'] ?? '',
    partial: data['partial'] == true,
    history: Map<String, int>.from(data['history'] ?? {}),
  );
  int streak(int goal, DateTime now) {
    var date = DateTime(now.year, now.month, now.day);
    if ((history[dayKey(date)] ?? 0) < goal) {
      date = DateTime(date.year, date.month, date.day - 1);
    }
    var days = 0;
    for (var i = 0; i < 7; i++) {
      if ((history[dayKey(date)] ?? 0) < goal) break;
      days++;
      date = DateTime(date.year, date.month, date.day - 1);
    }
    return days;
  }
}

class StepService extends ChangeNotifier with WidgetsBindingObserver {
  final MethodChannel channel;
  StepSnapshot snapshot = const StepSnapshot();
  bool busy = false, _disposed = false;
  Timer? _timer;
  StepService({this.channel = const MethodChannel('kg.adamrun/steps')});
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    if (_disposed) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
  }

  Future<void> refresh({bool request = false}) async {
    if (busy || _disposed) return;
    if (kIsWeb) {
      snapshot = const StepSnapshot(
        status: 'unsupported',
        source: 'Нужен телефон',
      );
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final map = await channel.invokeMapMethod<String, dynamic>('snapshot', {
        'request': request,
      });
      if (map != null) snapshot = StepSnapshot.fromMap(map);
    } on MissingPluginException {
      snapshot = const StepSnapshot(status: 'unsupported');
    } on PlatformException {
      snapshot = const StepSnapshot(status: 'error');
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
