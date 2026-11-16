import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../activity/activity_controller.dart';
import '../activity/route_model.dart';
import '../steps/step_service.dart';
import 'route_map.dart';
import '../profile/goal_sheet.dart';
import '../profile/profile_screen.dart';
import '../rankings/rankings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Api api;
  final Profile profile;
  final List<RunRoute> routes;
  final Map<String, dynamic> city;
  final SharedPreferences preferences;
  final VoidCallback onLogout;
  const HomeScreen({
    super.key,
    required this.api,
    required this.profile,
    required this.routes,
    required this.city,
    required this.preferences,
    required this.onLogout,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Profile _profile;
  late ActivityController _activity;
  final _steps = StepService();
  bool _walk = true, _expanded = false;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _activity = ActivityController(
      widget.routes,
      widget.preferences,
      _profile.id,
      api: widget.api,
    );
    _walk = _activity.active?.walk ?? true;
    _expanded = _activity.active != null;
    _steps.start();
  }

  @override
  void dispose() {
    _steps.dispose();
    _activity.dispose();
    super.dispose();
  }

  RunRoute get _route =>
      _activity.active ?? widget.routes.firstWhere((r) => r.walk == _walk);
  String _number(int n) => NumberFormat.decimalPattern('ru').format(n);
  String _time(Duration d) =>
      '${d.inHours > 0 ? '${d.inHours}:' : ''}${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  Future<void> _goal() async {
    final p = await showGoalSheet(context, widget.api, _profile.goal);
    if (p != null && mounted) {
      setState(() => _profile = p);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Новая цель сохранена')));
    }
  }

  Future<void> _account() async {
    setState(() => _tab = 2);
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimatedBuilder(
          animation: _activity,
          builder: (context, _) => Scaffold(
            appBar: AppBar(title: Text(_route.name)),
            body: Column(
              children: [
                Expanded(
                  child: RouteMap(
                    key: ValueKey('${_route.id}.${_activity.active != null}'),
                    route: _route,
                    city: widget.city,
                    active: _activity.active != null,
                    running: _activity.running,
                    heading: _activity.heading,
                    progress: _activity.fraction,
                    user: _activity.location,
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _activity.busy
                              ? 'Определяем старт…'
                              : _activity.running
                              ? '● Запись идёт · ${_time(_activity.elapsed)}'
                              : _activity.active != null
                              ? 'На паузе · ${_time(_activity.elapsed)}'
                              : 'Карта Бишкека доступна без интернета',
                          style: const TextStyle(color: AdamTheme.orange),
                        ),
                        if (_activity.message != null)
                          Text(
                            _activity.message!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _activity.busy
                              ? null
                              : () => _activity.progress?.complete == true
                                    ? _activity.finish()
                                    : _activity.running
                                    ? _activity.pause()
                                    : _activity.start(_route),
                          child: Text(
                            _activity.progress?.complete == true
                                ? 'Завершить'
                                : _activity.running
                                ? 'Пауза'
                                : _activity.active != null
                                ? 'Продолжить'
                                : _route.walk
                                ? 'Начать рисунок'
                                : 'Начать забег',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить прохождение?'),
        content: const Text(
          'Прогресс этой прогулки или забега будет удалён. Дневные шаги сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Продолжить позже'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (yes == true) await _activity.discard();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_steps, _activity]),
    builder: (context, _) {
      final steps = _steps.snapshot, now = DateTime.now();
      final count = steps.day == dayKey(now) ? steps.count : null;
      final route = _route, active = _activity.active != null;
      final streak = steps.streak(_profile.goal, now);
      return Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: Icon(Icons.leaderboard_outlined),
              label: 'Рейтинги',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Профиль',
            ),
          ],
        ),
        body: _tab == 1
            ? RankingsScreen(api: widget.api, routes: widget.routes)
            : _tab == 2
            ? ProfileScreen(
                api: widget.api,
                profile: _profile,
                onChanged: (p) => setState(() => _profile = p),
                onLogout: widget.onLogout,
                steps: _steps,
              )
            : SafeArea(
                child: RefreshIndicator(
                  color: AdamTheme.orange,
                  onRefresh: () async {
                    await _steps.refresh();
                    await _activity.sync();
                    final p = await widget.api.profile();
                    if (mounted) setState(() => _profile = p);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Brand(),
                                const SizedBox(height: 5),
                                Text(
                                  'Бишкек · Привет, ${_profile.nickname}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AdamTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: _account,
                            tooltip: 'Аккаунт',
                            icon: const Icon(Icons.person_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF252720),
                              AdamTheme.surface,
                              Color(0xFF10171D),
                            ],
                          ),
                          border: Border.all(color: const Color(0xFF4C4638)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'ТВОЙ ДЕНЬ / ${DateFormat('d MMMM', 'ru').format(now).toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1,
                                      color: AdamTheme.muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.local_fire_department_outlined,
                                  color: AdamTheme.orange,
                                  size: 17,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$streak дн. подряд',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AdamTheme.orange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                SizedBox(
                                  width: 132,
                                  height: 132,
                                  child: CustomPaint(
                                    painter: _Ring(
                                      (count ?? 0) / _profile.goal,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            count == null
                                                ? '—'
                                                : _number(count),
                                            style: AdamTheme.display(
                                              count != null && count >= 10000
                                                  ? 32
                                                  : 39,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'шагов',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AdamTheme.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Цель на сегодня',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AdamTheme.muted,
                                        ),
                                      ),
                                      InkWell(
                                        key: const Key('daily-goal'),
                                        onTap: _goal,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 5,
                                          ),
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  _number(_profile.goal),
                                                  style: AdamTheme.display(28),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.edit_outlined,
                                                size: 16,
                                                color: AdamTheme.muted,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Text(
                                        count == null
                                            ? 'Подключи шагомер'
                                            : count >= _profile.goal
                                            ? 'Цель достигнута!'
                                            : 'Ещё ${_number(_profile.goal - count)} шагов',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AdamTheme.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${_activity.xp} XP',
                                        style: const TextStyle(
                                          color: AdamTheme.orange,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (steps.status == 'ready')
                              Row(
                                children: [
                                  const Icon(
                                    Icons.sensors,
                                    size: 14,
                                    color: AdamTheme.orange,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${steps.source}${steps.partial ? ' · с момента подключения' : ''}',
                                      style: const TextStyle(
                                        color: AdamTheme.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  if (_steps.busy)
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1,
                                      ),
                                    ),
                                ],
                              )
                            else ...[
                              Text(
                                steps.status == 'unsupported'
                                    ? 'Шагомер доступен на телефоне с датчиком движения.'
                                    : steps.status == 'denied'
                                    ? 'Разреши доступ к движению в настройках телефона.'
                                    : steps.status == 'error'
                                    ? 'Не удалось прочитать шаги. Обнови данные.'
                                    : 'Разреши доступ к шагам — начнём считать твою активность.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AdamTheme.muted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (steps.status != 'unsupported')
                                OutlinedButton(
                                  onPressed: _steps.busy
                                      ? null
                                      : () => steps.status == 'denied'
                                            ? Geolocator.openAppSettings()
                                            : _steps.refresh(request: true),
                                  child: Text(
                                    _steps.busy
                                        ? 'Подключение…'
                                        : steps.status == 'denied'
                                        ? 'Открыть настройки'
                                        : 'Подключить шагомер',
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Week(snapshot: steps, goal: _profile.goal),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AdamTheme.surface,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: AdamTheme.border),
                        ),
                        child: Row(
                          children: [
                            _mode(
                              true,
                              Icons.directions_walk,
                              'Walk Quest',
                              active,
                            ),
                            _mode(
                              false,
                              Icons.timer_outlined,
                              'Run Race',
                              active,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              active
                                  ? 'ТВОЙ МАРШРУТ'
                                  : '${route.walk ? 'РИСУЙ ШАГАМИ' : 'ПОРА НА ПРОБЕЖКУ'} / БИШКЕК',
                              style: const TextStyle(
                                fontSize: 11,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w600,
                                color: AdamTheme.muted,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.route_outlined,
                            color: AdamTheme.orange,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AdamTheme.surface,
                          border: Border.all(color: const Color(0xFF976034)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: _expanded ? 350 : 205,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: RouteMap(
                                      key: ValueKey(
                                        '${route.id}.$_expanded.$active',
                                      ),
                                      route: route,
                                      city: widget.city,
                                      interactive: true,
                                      running: _activity.running,
                                      heading: _activity.heading,
                                      active: active,
                                      progress: active ? _activity.fraction : 0,
                                      user: _activity.location,
                                    ),
                                  ),
                                  Positioned(
                                    left: 12,
                                    top: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AdamTheme.background.withValues(
                                          alpha: .95,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            route.walk
                                                ? Icons.draw_outlined
                                                : Icons.flag_outlined,
                                            size: 15,
                                            color: AdamTheme.orange,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            route.walk
                                                ? (_activity.running
                                                      ? '● РИСУЕМ МАРШРУТ'
                                                      : _activity.busy
                                                      ? 'ОПРЕДЕЛЯЕМ СТАРТ'
                                                      : 'РИСУНОК НА КАРТЕ')
                                                : (_activity.running
                                                      ? '● ЗАБЕГ ИДЁТ'
                                                      : 'ПАРКОВЫЙ КРУГ'),
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 10,
                                    bottom: 28,
                                    child: IconButton.filledTonal(
                                      tooltip: _expanded
                                          ? 'Свернуть карту'
                                          : 'Развернуть карту',
                                      onPressed: _openMap,
                                      icon: Icon(
                                        _expanded
                                            ? Icons.close_fullscreen
                                            : Icons.open_in_full,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          route.name,
                                          style: AdamTheme.display(28),
                                        ),
                                      ),
                                      if (active)
                                        Text(
                                          '${(_activity.fraction * 100).floor()}%',
                                          style: AdamTheme.display(
                                            24,
                                          ).copyWith(color: AdamTheme.orange),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    '${(route.distance / 1000).toStringAsFixed(2).replaceAll('.', ',')} км · ${route.walk ? 'Центр Бишкека' : 'Парк им. Айтматова'}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AdamTheme.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    route.description,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AdamTheme.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (active) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: _activity.fraction,
                                        minHeight: 5,
                                        backgroundColor: AdamTheme.border,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _time(_activity.elapsed),
                                          style: AdamTheme.display(30),
                                        ),
                                        Text(
                                          _activity.running
                                              ? '● Запись идёт'
                                              : 'На паузе',
                                          style: TextStyle(
                                            color: _activity.running
                                                ? const Color(0xFF9ED9AA)
                                                : AdamTheme.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Icon(
                                          route.walk
                                              ? Icons.auto_awesome_outlined
                                              : Icons.emoji_events_outlined,
                                          color: AdamTheme.orange,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            route.walk
                                                ? (_activity.collected
                                                      ? 'Рисунок уже в коллекции'
                                                      : 'Рисунок в коллекцию · +200 XP')
                                                : _activity.best(route.id) ==
                                                      null
                                                ? 'Твой первый личный рекорд'
                                                : 'Лучшее время: ${_time(Duration(milliseconds: _activity.best(route.id)!))}',
                                            style: const TextStyle(
                                              color: AdamTheme.orange,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  if (_activity.syncMessage != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Text(
                                        _activity.syncMessage!,
                                        style: const TextStyle(
                                          color: AdamTheme.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (_activity.message != null) ...[
                                    Text(
                                      _activity.message!,
                                      style: const TextStyle(
                                        color: Color(0xFFFFBE83),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  FilledButton(
                                    onPressed: _activity.busy
                                        ? null
                                        : _activity.progress?.complete == true
                                        ? () => _activity.finish()
                                        : _activity.running
                                        ? () => _activity.pause()
                                        : () => _activity.start(route),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _activity.busy
                                              ? 'Определяем старт…'
                                              : _activity.progress?.complete ==
                                                    true
                                              ? 'Завершить'
                                              : _activity.running
                                              ? 'Пауза'
                                              : active
                                              ? 'Продолжить'
                                              : route.walk
                                              ? 'Начать рисунок'
                                              : 'Начать забег',
                                        ),
                                        Icon(
                                          _activity.running
                                              ? Icons.pause
                                              : Icons.arrow_outward,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (active)
                                    Center(
                                      child: TextButton(
                                        onPressed: _cancel,
                                        child: const Text(
                                          'Сбросить прохождение',
                                          style: TextStyle(
                                            color: AdamTheme.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Пробный маршрут · без партнёрских призов',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AdamTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AdamTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _activity.collected
                                  ? Icons.verified_outlined
                                  : Icons.draw_outlined,
                              color: AdamTheme.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Твоя коллекция',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _activity.collected
                                      ? 'Городская птица · рисунок открыт'
                                      : 'Пройди Walk Quest — открой первый рисунок',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AdamTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );
  Widget _mode(bool walk, IconData icon, String label, bool active) => Expanded(
    child: Semantics(
      selected: _walk == walk,
      child: TextButton(
        onPressed: active ? null : () => setState(() => _walk = walk),
        style: TextButton.styleFrom(
          backgroundColor: _walk == walk
              ? AdamTheme.orange
              : Colors.transparent,
          foregroundColor: _walk == walk
              ? AdamTheme.background
              : AdamTheme.muted,
          disabledForegroundColor: _walk == walk
              ? AdamTheme.background
              : AdamTheme.muted,
          minimumSize: const Size(0, 46),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Ring extends CustomPainter {
  final double progress;
  _Ring(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, paint..color = AdamTheme.border);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      paint..color = AdamTheme.orange,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress;
}

class _Week extends StatelessWidget {
  final StepSnapshot snapshot;
  final int goal;
  const _Week({required this.snapshot, required this.goal});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: List.generate(7, (i) {
        final d = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: 6 - i));
        final n = snapshot.history[dayKey(d)];
        return Expanded(
          child: Semantics(
            label:
                '${DateFormat('d MMMM', 'ru').format(d)}: ${n ?? 'нет данных'} шагов',
            child: Column(
              children: [
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 18,
                      height: n == null
                          ? 3
                          : math.max(3, 28 * (n / goal).clamp(0, 1)),
                      decoration: BoxDecoration(
                        color: i == 6 ? AdamTheme.orange : AdamTheme.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  i == 6 ? 'Сегодня' : DateFormat('EE', 'ru').format(d),
                  style: TextStyle(
                    fontSize: 10,
                    color: i == 6 ? Colors.white : AdamTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
