import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

Future<Profile?> showGoalSheet(BuildContext context, Api api, int goal) =>
    showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GoalSheet(api: api, goal: goal),
    );

class GoalSheet extends StatefulWidget {
  final Api api;
  final int goal;
  const GoalSheet({super.key, required this.api, required this.goal});
  @override
  State<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<GoalSheet> {
  late final _field = TextEditingController(text: '${widget.goal}');
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final p = await widget.api.setGoal(int.parse(_field.text));
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(_field.text) ?? 0;
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ТВОЯ ЦЕЛЬ', style: AdamTheme.display(28)),
              const SizedBox(height: 8),
              const Text('Шагов в день'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [3000, 5000, 8000, 10000, 15000]
                    .map(
                      (v) => ChoiceChip(
                        label: Text('$v'),
                        selected: n == v,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _field.text = '$v'),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('goal-input'),
                controller: _field,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(
                  labelText: 'Своя цель · от 1 000 до 50 000',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving || n < 1000 || n > 50000 ? null : _save,
                child: Text(_saving ? 'Сохраняем…' : 'Сохранить цель'),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
