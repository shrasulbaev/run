import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../steps/step_service.dart';
import 'goal_sheet.dart';

class PlayerAvatar extends StatelessWidget {
  final Api api;
  final String id, nickname;
  final String? version;
  final double radius;
  const PlayerAvatar({
    super.key,
    required this.api,
    required this.id,
    required this.nickname,
    this.version,
    this.radius = 24,
  });
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xff34302b),
    foregroundColor: AdamTheme.orange,
    child: ClipOval(
      child: version == null
          ? Text(
              nickname.isEmpty ? 'A' : nickname.characters.first.toUpperCase(),
              style: AdamTheme.display(radius),
            )
          : Image.network(
              api.photoUrl(id, version!),
              headers: api.photoHeaders,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) =>
                  Icon(Icons.person_outline, size: radius),
            ),
    ),
  );
}

String resultTime(num ms) {
  final d = Duration(milliseconds: ms.toInt());
  return '${d.inHours > 0 ? '${d.inHours}:' : ''}${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class ProfileScreen extends StatefulWidget {
  final Api api;
  final Profile profile;
  final ValueChanged<Profile> onChanged;
  final VoidCallback onLogout;
  final StepService steps;
  const ProfileScreen({
    super.key,
    required this.api,
    required this.profile,
    required this.onChanged,
    required this.onLogout,
    required this.steps,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _photoBusy = false;
  List<dynamic> _local = [];
  bool _localDrawing = false;
  final _picker = ImagePicker();
  @override
  void initState() {
    super.initState();
    _load();
    _recoverPhoto();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = jsonDecode(
        prefs.getString('local_history.${widget.profile.id}') ?? '[]',
      ) as List;
      if (mounted) {
        setState(() {
          _local = local;
          _localDrawing =
              prefs.getBool('drawing.${widget.profile.id}.city-bird') == true;
        });
      }
      final p = await widget.api.profile();
      final data = await widget.api.getData('/me/activity');
      if (!mounted) return;
      widget.onChanged(p);
      setState(() {
        _data = data;
        final synced = (data['activities'] as List).map((a) => a['id']).toSet();
        _local.removeWhere((a) => synced.contains(a['id']));
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _recoverPhoto() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.files?.isNotEmpty == true) await _upload(lost.files!.first);
    } catch (_) {
      /* Unsupported on web/iOS; normal selection still works. */
    }
  }

  Future<void> _upload(XFile? file) async {
    if (file == null) return;
    setState(() => _photoBusy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 3000000) {
        throw const ApiException('Фото слишком большое. Выберите другое.');
      }
      final p = await widget.api.photo(bytes);
      if (mounted) widget.onChanged(p);
    } catch (e) {
      if (mounted) _notice(e.toString());
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _pickPhoto() async {
    try {
      await _upload(
        await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
          requestFullMetadata: false,
        ),
      );
    } catch (e) {
      if (mounted) _notice('Не удалось открыть фото. Проверьте разрешения.');
    }
  }

  Future<void> _edit() async {
    final p = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfile(api: widget.api, profile: widget.profile),
    );
    if (p != null && mounted) widget.onChanged(p);
  }

  Future<void> _goal() async {
    final p = await showGoalSheet(context, widget.api, widget.profile.goal);
    if (p != null && mounted) widget.onChanged(p);
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
      if (mounted) widget.onLogout();
    } catch (e) {
      if (mounted) _notice(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final data = _data;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('ТВОЙ ПРОФИЛЬ', style: AdamTheme.display(30)),
            const SizedBox(height: 24),
            Row(
              children: [
                Stack(
                  children: [
                    PlayerAvatar(
                      api: widget.api,
                      id: p.id,
                      nickname: p.nickname,
                      version: p.avatarVersion,
                      radius: 42,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        onPressed: _photoBusy ? null : _pickPhoto,
                        icon: Icon(
                          _photoBusy
                              ? Icons.hourglass_top
                              : Icons.add_a_photo_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nickname, style: AdamTheme.display(29)),
                      Text(
                        p.city,
                        style: const TextStyle(color: AdamTheme.muted),
                      ),
                      TextButton(
                        onPressed: _edit,
                        child: const Text('Редактировать профиль'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_photoBusy) const LinearProgressIndicator(),
            if (p.bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(p.bio),
              ),
            if (p.avatarVersion != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _photoBusy
                      ? null
                      : () async {
                          try {
                            final changed = await widget.api.photo(null);
                            if (mounted) widget.onChanged(changed);
                          } catch (e) {
                            if (mounted) _notice(e.toString());
                          }
                        },
                  child: const Text('Удалить фото'),
                ),
              ),
            const SizedBox(height: 16),
            _card(
              Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.flag_outlined,
                      color: AdamTheme.orange,
                    ),
                    title: const Text('Цель на день'),
                    subtitle: Text('${p.goal} шагов'),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: _goal,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Контакт для входа'),
                    subtitle: Text(
                      [p.phone, p.email].where((s) => s.isNotEmpty).join('\n'),
                    ),
                  ),
                  const Text(
                    'Контакты, цель и история видны только тебе. Участники видят фото, никнейм, достижения и пройденные карты.',
                    style: TextStyle(color: AdamTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('ТВОЙ РИТМ', style: AdamTheme.display(23)),
            const SizedBox(height: 12),
            if (data != null)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _stat('${data['total']}', 'финишей'),
                  _stat(
                    ((data['distance_m'] as num) / 1000).toStringAsFixed(1),
                    'км по трассам',
                  ),
                  _stat('${data['drawings']}', 'рисунков'),
                ],
              ),
            if (_error != null)
              _card(
                Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              )
            else if (data == null)
              const LinearProgressIndicator(),
            const SizedBox(height: 22),
            Text('ДОСТИЖЕНИЯ', style: AdamTheme.display(23)),
            const SizedBox(height: 10),
            ..._badges(data?['achievements'] as List? ?? []),
            const SizedBox(height: 20),
            Text('КОЛЛЕКЦИЯ РИСУНКОВ', style: AdamTheme.display(23)),
            const SizedBox(height: 10),
            _card(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.draw_outlined,
                  color: ((data?['drawings'] ?? 0) > 0 || _localDrawing)
                      ? AdamTheme.orange
                      : AdamTheme.muted,
                ),
                title: const Text('Городская птица'),
                subtitle: Text(
                  ((data?['drawings'] ?? 0) > 0 || _localDrawing)
                      ? 'Рисунок собран · Бишкек'
                      : 'Пройди Walk Quest, чтобы открыть рисунок',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('ИСТОРИЯ МАРШРУТОВ', style: AdamTheme.display(23)),
            const SizedBox(height: 10),
            if ((data?['activities'] as List? ?? []).isEmpty)
              const Text(
                'Здесь появятся завершённые и синхронизированные маршруты.',
                style: TextStyle(color: AdamTheme.muted),
              ),
            for (final a in _local)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.phone_android,
                  color: AdamTheme.muted,
                ),
                title: Text(a['route_name']),
                subtitle: const Text(
                  'Сохранено на устройстве · ещё не подтверждено сервером',
                ),
                trailing: Text(resultTime(a['elapsed_ms'])),
              ),
            for (final a in data?['activities'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  a['mode'] == 'walk'
                      ? Icons.directions_walk
                      : Icons.directions_run,
                  color: AdamTheme.orange,
                ),
                title: Text(a['route_name']),
                subtitle: Text(
                  '${DateFormat('dd.MM · HH:mm').format(DateTime.parse(a['completed_at']).toLocal())}\n${a['ranked'] == true ? 'В рейтинге' : 'Личный результат'}',
                ),
                trailing: Text(resultTime(a['elapsed_ms'])),
              ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (_) => _StepCheck(steps: widget.steps),
              ),
              child: const Text('Проверить шагомер · 100 шагов'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _logout,
              child: const Text('Выйти из аккаунта'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Тестовая версия · вход по коду 00000',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AdamTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _card(Widget child) => Material(
  color: AdamTheme.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: const BorderSide(color: AdamTheme.border),
  ),
  child: Padding(padding: const EdgeInsets.all(16), child: child),
);
Widget _stat(String value, String label) => SizedBox(
  width: 100,
  child: _card(
    Column(
      children: [
        Text(value, style: AdamTheme.display(24)),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AdamTheme.muted),
        ),
      ],
    ),
  ),
);
List<Widget> _badges(List items) => items.isEmpty
    ? [
        const Text(
          'Первый финиш откроет первое достижение.',
          style: TextStyle(color: AdamTheme.muted),
        ),
      ]
    : items
          .map<Widget>(
            (a) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.workspace_premium_outlined,
                color: AdamTheme.orange,
              ),
              title: Text(a['name']),
              subtitle: Text(a['description']),
            ),
          )
          .toList();

class _EditProfile extends StatefulWidget {
  final Api api;
  final Profile profile;
  const _EditProfile({required this.api, required this.profile});
  @override
  State<_EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<_EditProfile> {
  late final _name = TextEditingController(text: widget.profile.nickname),
      _city = TextEditingController(text: widget.profile.city),
      _bio = TextEditingController(text: widget.profile.bio);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ЭТО ТЫ', style: AdamTheme.display(30)),
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'Никнейм'),
          ),
          TextField(
            controller: _city,
            enabled: !_busy,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Город'),
          ),
          TextField(
            controller: _bio,
            enabled: !_busy,
            maxLength: 250,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'О себе · видно только тебе',
            ),
          ),
          if (_error != null) Text(_error!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_name.text.trim().length < 2) {
                      setState(() => _error = 'Никнейм: минимум 2 символа');
                      return;
                    }
                    setState(() => _busy = true);
                    try {
                      final p = await widget.api.editProfile(
                        _name.text.trim(),
                        _city.text.trim(),
                        _bio.text.trim(),
                      );
                      if (context.mounted) Navigator.pop(context, p);
                    } catch (e) {
                      if (mounted) setState(() => _error = e.toString());
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    ),
  );
}

class _StepCheck extends StatefulWidget {
  final StepService steps;
  const _StepCheck({required this.steps});
  @override
  State<_StepCheck> createState() => _StepCheckState();
}

class _StepCheckState extends State<_StepCheck> {
  int? _baseline;
  String? _day;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.steps,
    builder: (context, _) {
      final s = widget.steps.snapshot;
      final delta = _baseline == null || _day != s.day
          ? null
          : ((s.count ?? _baseline!) - _baseline!).clamp(0, 100000);
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ПРОВЕРКА ШАГОМЕРА', style: AdamTheme.display(26)),
            const SizedBox(height: 12),
            const Text(
              'Положи телефон в карман, нажми «Начать» и пройди ровно 100 шагов, считая их сам. Затем подожди 10 секунд: датчик может отдавать шаги пачкой.',
            ),
            const SizedBox(height: 20),
            Text(delta == null ? '—' : '$delta', style: AdamTheme.display(50)),
            Text(
              s.source,
              style: const TextStyle(color: AdamTheme.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: s.count == null
                  ? null
                  : () => setState(() {
                      _baseline = s.count;
                      _day = s.day;
                    }),
              child: Text(
                _baseline == null ? 'Начать проверку' : 'Начать заново',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Проверка не меняет дневные шаги. Результат поможет оценить датчик именно на твоём телефоне.',
              style: TextStyle(color: AdamTheme.muted, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}

class PublicProfileScreen extends StatefulWidget {
  final Api api;
  final String userId;
  const PublicProfileScreen({
    super.key,
    required this.api,
    required this.userId,
  });
  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Future<Map<String, dynamic>> _future = widget.api.getData(
    '/users/${widget.userId}',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Участник')),
    body: FutureBuilder(
      future: _future,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(
                () => _future = widget.api.getData('/users/${widget.userId}'),
              ),
              child: Text('${s.error}\nПовторить'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: PlayerAvatar(
                api: widget.api,
                id: d['id'],
                nickname: d['nickname'],
                version: d['avatar_version'],
                radius: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              d['nickname'],
              textAlign: TextAlign.center,
              style: AdamTheme.display(32),
            ),
            const SizedBox(height: 28),
            Text('ДОСТИЖЕНИЯ', style: AdamTheme.display(24)),
            ..._badges(d['achievements']),
            const SizedBox(height: 24),
            Text('ПРОЙДЕННЫЕ КАРТЫ', style: AdamTheme.display(24)),
            if ((d['completed_routes'] as List).isEmpty)
              const Text('Пока нет завершённых маршрутов.'),
            for (final r in d['completed_routes'])
              ListTile(
                leading: Icon(
                  r['mode'] == 'walk'
                      ? Icons.draw_outlined
                      : Icons.flag_outlined,
                  color: AdamTheme.orange,
                ),
                title: Text(r['name']),
                subtitle: Text(
                  '${((r['distance_m'] as num) / 1000).toStringAsFixed(2)} км',
                ),
              ),
          ],
        );
      },
    ),
  );
}
