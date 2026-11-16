import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../activity/route_model.dart';
import '../profile/profile_screen.dart';

class RankingsScreen extends StatefulWidget {
  final Api api;
  final List<RunRoute> routes;
  const RankingsScreen({super.key, required this.api, required this.routes});
  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  late RunRoute _route = widget.routes.first;
  bool _all = false;
  late Future<Map<String, dynamic>> _future = _fetch();
  Future<Map<String, dynamic>> _fetch() => widget.api.getData(
    '/rankings/${_route.id}?period=${_all ? 'all' : 'month'}',
  );
  void _reload() => setState(() => _future = _fetch());
  String _score(dynamic score) =>
      _route.walk ? '$score дн.' : resultTime(score as num);
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ГОРОД В ДВИЖЕНИИ', style: AdamTheme.display(30)),
              const SizedBox(height: 5),
              const Text(
                'Рейтинг всех игроков · Бишкек',
                style: TextStyle(color: AdamTheme.muted),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _route.id,
                isExpanded: true,
                items: widget.routes
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text('${r.walk ? 'Walk' : 'Run'} · ${r.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  _route = widget.routes.firstWhere((r) => r.id == id);
                  _reload();
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Этот месяц')),
                  ButtonSegment(value: true, label: Text('Всё время')),
                ],
                selected: {_all},
                onSelectionChanged: (v) {
                  _all = v.first;
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _future,
            builder: (context, s) {
              if (s.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.error.toString()),
                        TextButton(
                          onPressed: _reload,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final d = s.data!;
              final entries = d['entries'] as List;
              final mine = d['me'];
              return RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdamTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['rule']),
                          const SizedBox(height: 10),
                          Text(
                            '${d['participants']} участников · ${d['rewards']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AdamTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (mine != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: AdamTheme.orange),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bolt, color: AdamTheme.orange),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Твоё место · ${mine['rank']}'),
                            ),
                            Text(
                              _score(mine['score']),
                              style: AdamTheme.display(23),
                            ),
                          ],
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Заверши маршрут с подтверждённым стартом, чтобы попасть в таблицу.',
                          style: TextStyle(color: AdamTheme.muted),
                        ),
                      ),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 45),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.emoji_events_outlined,
                              size: 60,
                              color: AdamTheme.orange,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'ПЕРВОЕ МЕСТО СВОБОДНО',
                              style: AdamTheme.display(24),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Стань первым на этой трассе.',
                              style: TextStyle(color: AdamTheme.muted),
                            ),
                          ],
                        ),
                      ),
                    for (final e in entries)
                      Card(
                        color: e['is_me'] == true
                            ? const Color(0xff30271f)
                            : AdamTheme.surface,
                        child: ListTile(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicProfileScreen(
                                api: widget.api,
                                userId: e['id'],
                              ),
                            ),
                          ),
                          leading: SizedBox(
                            width: 80,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${e['rank']}',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                      color: e['rank'] <= 3
                                          ? AdamTheme.orange
                                          : AdamTheme.muted,
                                    ),
                                  ),
                                ),
                                PlayerAvatar(
                                  api: widget.api,
                                  id: e['id'],
                                  nickname: e['nickname'],
                                  version: e['avatar_version'],
                                  radius: 21,
                                ),
                              ],
                            ),
                          ),
                          title: Text(
                            e['nickname'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: e['rank'] <= 3
                              ? const Text(
                                  'В тройке лидеров',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AdamTheme.orange,
                                  ),
                                )
                              : null,
                          trailing: Text(
                            _score(e['score']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
