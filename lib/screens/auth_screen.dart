import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String _mode = 'choice'; // choice, register, login
  bool _busy = false;
  String _status = '';

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _remember = true;
  bool _showPassword = false;
  bool _showKey = false;
  bool _showToken = false;

  final _ruLabels = {
    'title': 'BLACK BOX',
    'subtitle': 'Выберите действие',
    'register': 'Регистрация',
    'login': 'Вход',
    'nickname': 'Никнейм',
    'email': 'Почта',
    'password': 'Пароль',
    'key': 'Уникальный ключ',
    'token': 'GitHub токен',
    'token_hint': 'Токен нужен для доступа к blackbox-keys',
    'remember': 'Запомнить',
    'show': 'Показать',
    'activate': 'Активировать',
    'enter': 'Войти',
    'back': '← Назад',
    'fill_fields': 'Заполните все поля',
    'unknown_error': 'Неизвестная ошибка',
  };

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    final token = _tokenCtrl.text.trim();

    if (name.isEmpty || password.isEmpty || key.isEmpty || token.isEmpty ||
        (_mode == 'register' && _emailCtrl.text.trim().isEmpty)) {
      setState(() => _status = _ruLabels['fill_fields']!);
      return;
    }

    setState(() {
      _busy = true;
      _status = '';
    });

    try {
      final tokRes = await coreCall('set_github_token', {'token': token});
      if (tokRes['ok'] != true) {
        setState(() => _status = 'Не удалось сохранить токен: ${tokRes['error']}');
        return;
      }

      final Map<String, dynamic> args = {
        'name': name,
        'password': password,
        'key': key,
        'remember': _remember,
      };
      if (_mode == 'register') {
        args['email'] = _emailCtrl.text.trim();
      }

      final res = await coreCall(_mode == 'register' ? 'register' : 'login', args);
      if (res['ok'] == true) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/launcher');
        }
        return;
      }
      setState(() => _status = _mapError(res['error']?.toString() ?? 'unknown'));
    } catch (e) {
      setState(() => _status = 'Ошибка канала: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'no_connection':
        return 'Нет связи с сервером. Проверьте интернет.';
      case 'invalid_key':
      case 'not_registered':
        return 'Неверный ключ или пользователь.';
      case 'wrong_credentials':
        return 'Неверный никнейм или пароль.';
      default:
        return _ruLabels['unknown_error']!;
    }
  }

  void _setMode(String mode) {
    setState(() {
      _mode = mode;
      _status = '';
    });
  }

  Widget _buildChoice() {
    return Column(
      children: [
        Text(_ruLabels['title']!, style: AppTheme.header()),
        const SizedBox(height: 16),
        Text(_ruLabels['subtitle']!, style: AppTheme.body()),
        const SizedBox(height: 50),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _setMode('register'),
            child: Text(_ruLabels['register']!),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _setMode('login'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.card,
              foregroundColor: AppTheme.text,
            ),
            child: Text(_ruLabels['login']!),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final isReg = _mode == 'register';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isReg ? _ruLabels['register']! : _ruLabels['login']!,
              style: AppTheme.header()),
          const SizedBox(height: 30),
          _field(_ruLabels['nickname']!, _nameCtrl),
          if (isReg) ...[
            const SizedBox(height: 12),
            _field(_ruLabels['email']!, _emailCtrl, keyboard: TextInputType.emailAddress),
          ],
          const SizedBox(height: 12),
          _field(
            _ruLabels['password']!,
            _passwordCtrl,
            obscure: !_showPassword,
            toggle: () => setState(() => _showPassword = !_showPassword),
            show: _showPassword,
          ),
          const SizedBox(height: 12),
          _field(
            _ruLabels['key']!,
            _keyCtrl,
            obscure: !_showKey,
            toggle: () => setState(() => _showKey = !_showKey),
            show: _showKey,
          ),
          const SizedBox(height: 12),
          _field(
            _ruLabels['token']!,
            _tokenCtrl,
            obscure: !_showToken,
            toggle: () => setState(() => _showToken = !_showToken),
            show: _showToken,
          ),
          const SizedBox(height: 4),
          Text(_ruLabels['token_hint']!, style: AppTheme.small(color: AppTheme.muted)),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? true),
            title: Text(_ruLabels['remember']!),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          if (_status.isNotEmpty)
            Text(_status, style: AppTheme.small(color: AppTheme.down)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(isReg ? _ruLabels['activate']! : _ruLabels['enter']!),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _setMode('choice'),
            child: Text(_ruLabels['back']!, style: AppTheme.small(color: AppTheme.muted)),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    VoidCallback? toggle,
    bool show = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: toggle != null
            ? IconButton(
                icon: Icon(show ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.muted, size: 20),
                onPressed: toggle,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _mode == 'choice' ? _buildChoice() : _buildForm(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _keyCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }
}
