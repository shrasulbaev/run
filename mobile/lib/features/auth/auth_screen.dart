import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

class AuthScreen extends StatefulWidget {
  final Api api;
  final ValueChanged<Profile> onSignedIn;
  const AuthScreen({super.key, required this.api, required this.onSignedIn});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _name = TextEditingController(),
      _code = TextEditingController();
  bool _register = true, _busy = false;
  String? _challenge, _error;
  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_challenge == null) {
        final id = await widget.api.requestCode(_email.text);
        if (mounted) setState(() => _challenge = id);
      } else {
        final user = await widget.api.verify(
          _challenge!,
          _code.text,
          _register ? _name.text : null,
        );
        if (mounted) widget.onSignedIn(user);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Не удалось войти. Попробуйте ещё раз.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Brand(size: 44),
                  const SizedBox(height: 12),
                  const Text(
                    'Твой город. Твой маршрут.',
                    style: TextStyle(color: AdamTheme.muted, fontSize: 17),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    _challenge != null
                        ? 'ТВОЙ КОД'
                        : _register
                        ? 'НАЧНИ ДВИЖЕНИЕ'
                        : 'С ВОЗВРАЩЕНИЕМ',
                    style: AdamTheme.display(32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _challenge != null
                        ? 'Подтверди вход для ${_email.text.trim()}'
                        : 'Прогулки с рисунками и забеги по Бишкеку.',
                    style: const TextStyle(color: AdamTheme.muted),
                  ),
                  const SizedBox(height: 28),
                  if (_challenge == null) ...[
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Никнейм',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                        maxLength: 32,
                        validator: (v) => (v?.trim().length ?? 0) < 2
                            ? 'Не менее 2 символов'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (v) =>
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Введите корректный email',
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ] else ...[
                    TextFormField(
                      key: const Key('otp'),
                      controller: _code,
                      autofocus: true,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textAlign: TextAlign.center,
                      style: AdamTheme.display(38).copyWith(letterSpacing: 16),
                      maxLength: 5,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Код из 5 цифр',
                        counterText: '',
                      ),
                      validator: (v) =>
                          v?.length == 5 ? null : 'Введите все 5 цифр',
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const Key('auth-error'),
                      style: const TextStyle(color: Color(0xFFFFAA91)),
                      semanticsLabel: 'Ошибка: $_error',
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_challenge != null ? 'Войти' : 'Получить код'),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              if (_challenge != null) {
                                _challenge = null;
                                _code.clear();
                              } else {
                                _register = !_register;
                              }
                              _error = null;
                            }),
                      child: Text(
                        _challenge != null
                            ? 'Изменить email / запросить новый код'
                            : _register
                            ? 'Уже есть аккаунт? Войти'
                            : 'Создать аккаунт',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AdamTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          color: AdamTheme.orange,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Тестовый вход · код 00000\nПисьмо пока не отправляется.',
                            style: TextStyle(
                              color: AdamTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
