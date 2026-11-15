import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'features/activity/route_model.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AdamTheme.background,
    ),
  );
  runApp(const AdamApp());
}

class AdamApp extends StatefulWidget {
  const AdamApp({super.key});
  @override
  State<AdamApp> createState() => _AdamAppState();
}

class _AdamAppState extends State<AdamApp> {
  final Api _api = Api();
  Profile? _user;
  List<RunRoute>? _routes;
  Map<String, dynamic>? _city;
  SharedPreferences? _prefs;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _api.onSessionExpired = () {
      if (mounted) setState(() => _user = null);
    };
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    var stage = 'routes';
    try {
      _routes = await RunRoute.load();
      stage = 'map';
      _city = jsonDecode(
        await rootBundle.loadString('assets/maps/bishkek.geojson'),
      );
      stage = 'preferences';
      _prefs = await SharedPreferences.getInstance();
      stage = 'session';
      _user = await _api.restore();
    } catch (e) {
      debugPrint(
        'Startup failed: $stage, ${e.runtimeType}${e is PlatformException ? ', code=${e.code}' : ''}',
      );
      _error = 'Не удалось открыть приложение. Попробуйте снова.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (_loading) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      home = Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    } else if (_user == null) {
      home = AuthScreen(
        api: _api,
        onSignedIn: (user) => setState(() => _user = user),
      );
    } else {
      home = HomeScreen(
        key: ValueKey(_user!.id),
        api: _api,
        profile: _user!,
        routes: _routes!,
        city: _city!,
        preferences: _prefs!,
        onLogout: () => setState(() => _user = null),
      );
    }
    return MaterialApp(
      title: 'ADAM RUN',
      debugShowCheckedModeBanner: false,
      theme: AdamTheme.theme,
      home: home,
    );
  }
}
