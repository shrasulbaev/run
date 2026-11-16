import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Profile {
  final String id, email, phone, nickname, city, bio;
  final String? avatarVersion;
  final int goal;
  Profile.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      email = j['email'] ?? '',
      phone = j['phone'] ?? '',
      nickname = j['nickname'],
      goal = j['step_goal'],
      city = j['city'] ?? 'Бишкек',
      bio = j['bio'] ?? '',
      avatarVersion = j['avatar_version'];
}

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: 'adam.session');
  @override
  Future<void> write(String value) =>
      storage.write(key: 'adam.session', value: value);
  @override
  Future<void> clear() => storage.delete(key: 'adam.session');
}

class Api {
  static String get defaultBase =>
      const String.fromEnvironment('API_BASE_URL').isNotEmpty
      ? const String.fromEnvironment('API_BASE_URL')
      : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://127.0.0.1:8000';
  final http.Client client;
  final TokenStore store;
  final String base;
  final Duration requestTimeout;
  Map<String, dynamic>? session;
  Future<void>? _refreshing;
  VoidCallback? onSessionExpired;
  Api({
    http.Client? client,
    TokenStore? store,
    String? base,
    this.requestTimeout = const Duration(seconds: 90),
  }) : client = client ?? http.Client(),
       store = store ?? SecureTokenStore(),
       base = base ?? defaultBase;
  Profile? get cachedProfile =>
      session?['user'] == null ? null : Profile.fromJson(session!['user']);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authorized = false,
    bool retry = true,
  }) async {
    try {
      final request = http.Request(method, Uri.parse('$base$path'))
        ..headers['Content-Type'] = 'application/json';
      if (authorized && session != null) {
        request.headers['Authorization'] = 'Bearer ${session!['access_token']}';
      }
      if (body != null) request.body = jsonEncode(body);
      // The free hosting service may need a minute to wake from idle. Bound
      // the complete response, including body delivery; never replay POSTs.
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
      if (response.statusCode == 401 &&
          authorized &&
          retry &&
          session != null) {
        await (_refreshing ??= _refresh().whenComplete(
          () => _refreshing = null,
        ));
        return await _send(
          method,
          path,
          body: body,
          authorized: true,
          retry: false,
        );
      }
      if (response.statusCode >= 400) {
        dynamic decoded;
        try {
          decoded = jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          // A hosting gateway may respond with an HTML error page.
        }
        final detail = decoded is Map ? decoded['detail'] : null;
        if (response.statusCode == 401 && authorized) {
          await clear();
          onSessionExpired?.call();
        }
        throw ApiException(
          detail is String
              ? detail
              : response.statusCode >= 500
              ? 'Сервер запускается или временно недоступен. Повторите через минуту.'
              : 'Проверьте введённые данные',
          response.statusCode,
        );
      }
      return response.body.isEmpty
          ? {}
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      throw const ApiException(
        'Сервер не успел запуститься. Повторите через минуту.',
      );
    } on FormatException {
      throw const ApiException('Сервер ещё не готов. Повторите через минуту.');
    } on http.ClientException {
      throw const ApiException('Нет связи с сервером. Проверьте подключение.');
    }
  }

  Future<void> _refresh() async {
    try {
      final data = await _send(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': session!['refresh_token']},
      );
      session = data;
      await store.write(jsonEncode(data));
    } on ApiException catch (e) {
      if (e.status == 401) {
        await clear();
        onSessionExpired?.call();
      }
      rethrow;
    }
  }

  Future<Profile?> restore() async {
    final raw = await store.read();
    if (raw == null) return null;
    try {
      session = jsonDecode(raw);
    } on FormatException {
      await clear();
      return null;
    }
    try {
      return await profile();
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      return cachedProfile; // Native step data and downloaded routes remain available offline.
    }
  }

  Future<String> requestCode(String email, {bool phone = false}) async =>
      (await _send(
        'POST',
        '/auth/request-code',
        body: {
          'identifier': email.trim(),
          'channel': phone ? 'phone' : 'email',
        },
      ))['challenge_id'];
  Future<Profile> verify(
    String challenge,
    String code,
    String? nickname,
  ) async {
    session = await _send(
      'POST',
      '/auth/verify',
      body: {
        'challenge_id': challenge,
        'code': code,
        if (nickname != null) 'nickname': nickname.trim(),
      },
    );
    await store.write(jsonEncode(session));
    return cachedProfile!;
  }

  Future<Profile> profile() async {
    final data = await _send('GET', '/me', authorized: true);
    session!['user'] = data;
    await store.write(jsonEncode(session));
    return Profile.fromJson(data);
  }

  Future<Profile> setGoal(int goal) async {
    final data = await _send(
      'PATCH',
      '/me/goal',
      body: {'step_goal': goal},
      authorized: true,
    );
    session!['user'] = data;
    await store.write(jsonEncode(session));
    return Profile.fromJson(data);
  }

  Future<Map<String, dynamic>> getData(String path) =>
      _send('GET', path, authorized: true);
  Future<Map<String, dynamic>> postData(
    String path,
    Map<String, dynamic> body,
  ) => _send('POST', path, body: body, authorized: true);
  Map<String, String> get photoHeaders => {
    'Authorization': 'Bearer ${session?['access_token']}',
  };
  String photoUrl(String id, String version) =>
      '$base/users/$id/photo?v=$version';
  Future<Profile> editProfile(String nickname, String city, String bio) async {
    final data = await _send(
      'PATCH',
      '/me/profile',
      authorized: true,
      body: {'nickname': nickname, 'city': city, 'bio': bio},
    );
    return _saveProfile(data);
  }

  Future<Profile> photo(Uint8List? bytes) async {
    final data = await postData('/me/photo', {
      'image_base64': bytes == null ? null : base64Encode(bytes),
    });
    return _saveProfile(data);
  }

  Future<Profile> _saveProfile(Map<String, dynamic> data) async {
    session!['user'] = data;
    await store.write(jsonEncode(session));
    return Profile.fromJson(data);
  }

  Future<void> logout() async {
    if (session != null) {
      await _send(
        'POST',
        '/auth/logout',
        body: {'refresh_token': session!['refresh_token']},
        authorized: true,
      );
    }
    await clear();
  }

  Future<void> clear() async {
    session = null;
    await store.clear();
  }
}
