import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/ctrlchat_state.dart';

enum _AuthMode { login, register }

enum _LoginStep { credentials, code }

enum _RegisterStep { email, code, password, profile }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.stateController});

  final CtrlChatState stateController;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  _AuthMode _mode = _AuthMode.login;
  _LoginStep _loginStep = _LoginStep.credentials;
  _RegisterStep _registerStep = _RegisterStep.email;

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _loginCodeController = TextEditingController();

  final _registerEmailController = TextEditingController();
  final _registerCodeController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerPasswordConfirmController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    widget.stateController.addListener(_authStateListener);
  }

  @override
  void dispose() {
    widget.stateController.removeListener(_authStateListener);
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _loginCodeController.dispose();
    _registerEmailController.dispose();
    _registerCodeController.dispose();
    _registerPasswordController.dispose();
    _registerPasswordConfirmController.dispose();
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _authStateListener() {
    final state = widget.stateController;
    if (!mounted) {
      return;
    }
    if (state.isAuthenticated) {
      context.go('/app');
    }
  }

  Future<void> _showError(Object error) async {
    if (!mounted) {
      return;
    }
    final message = error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickAvatar() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      return;
    }
    setState(() {
      _avatarBytes = bytes;
    });
  }

  Future<void> _handleLoginCredentials() async {
    try {
      await widget.stateController.loginRequest(
        email: _loginEmailController.text.trim(),
        password: _loginPasswordController.text,
      );
      setState(() {
        _loginStep = _LoginStep.code;
      });
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _handleLoginCode() async {
    try {
      await widget.stateController.loginVerify(
        code: _loginCodeController.text.trim(),
      );
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _handleRegisterEmail() async {
    try {
      await widget.stateController.registerRequestCode(
        email: _registerEmailController.text.trim(),
      );
      setState(() {
        _registerStep = _RegisterStep.code;
      });
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _handleRegisterCode() async {
    try {
      await widget.stateController.registerVerifyCode(
        email: _registerEmailController.text.trim(),
        code: _registerCodeController.text.trim(),
      );
      setState(() {
        _registerStep = _RegisterStep.password;
      });
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _handleRegisterPassword() async {
    try {
      await widget.stateController.registerSetPassword(
        password: _registerPasswordController.text,
        passwordConfirm: _registerPasswordConfirmController.text,
      );
      setState(() {
        _registerStep = _RegisterStep.profile;
      });
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _handleRegisterProfile() async {
    try {
      String? avatarUrl;
      if (_avatarBytes != null) {
        final encoded = base64Encode(_avatarBytes!);
        avatarUrl = 'data:image/png;base64,$encoded';
      }
      await widget.stateController.registerCompleteProfile(
        displayName: _displayNameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
        bio: _bioController.text.trim(),
        avatarUrl: avatarUrl,
      );
    } catch (error) {
      await _showError(error);
    }
  }

  Widget _buildStepCardSwitcher({
    required Key activeKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 440),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (stepChild, animation) {
        return AnimatedBuilder(
          animation: animation,
          child: stepChild,
          builder: (context, animatedChild) {
            final t = animation.value.clamp(0.0, 1.0);
            final incoming = stepChild.key == activeKey;
            final dy = incoming
                ? (lerpDouble(-0.24, 0, t) ?? 0)
                : (lerpDouble(0, 0.24, 1 - t) ?? 0);
            return Opacity(
              opacity: t,
              child: FractionalTranslation(
                translation: Offset(0, dy),
                child: animatedChild,
              ),
            );
          },
        );
      },
      child: child,
    );
  }

  Widget _buildLoginCard(CtrlChatState state) {
    final stepKey = ValueKey<String>('login-${_loginStep.name}');
    final title = _loginStep == _LoginStep.credentials
        ? 'Вход'
        : '2FA подтверждение';
    final body = _loginStep == _LoginStep.credentials
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GlassInput(
                controller: _loginEmailController,
                hint: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _GlassInput(
                controller: _loginPasswordController,
                hint: 'Пароль',
                obscure: true,
              ),
              const SizedBox(height: 18),
              _PrimaryButton(
                label: state.loading ? 'Проверяем...' : 'Войти',
                onPressed: state.loading ? null : _handleLoginCredentials,
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GlassInput(
                controller: _loginCodeController,
                hint: '6-значный код',
                keyboardType: TextInputType.number,
              ),
              if (state.devCodeHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  'DEV CODE: ${state.devCodeHint}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _PrimaryButton(
                label: state.loading ? 'Подтверждаем...' : 'Подтвердить',
                onPressed: state.loading ? null : _handleLoginCode,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: state.loading
                    ? null
                    : () {
                        setState(() {
                          _loginStep = _LoginStep.credentials;
                          _loginCodeController.clear();
                        });
                      },
                child: const Text('Назад'),
              ),
            ],
          );
    return _buildStepCardSwitcher(
      activeKey: stepKey,
      child: _AuthCardFrame(
        key: stepKey,
        title: title,
        subtitle: _loginStep == _LoginStep.credentials
            ? 'Пароль + код из письма обязательны'
            : 'Введите код подтверждения из письма',
        child: body,
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Нет аккаунта?',
              style: TextStyle(color: Colors.white70),
            ),
            TextButton(
              onPressed: state.loading
                  ? null
                  : () {
                      setState(() {
                        _mode = _AuthMode.register;
                      });
                    },
              child: const Text('Зарегистрироваться'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterCard(CtrlChatState state) {
    final stepKey = ValueKey<String>('register-${_registerStep.name}');
    final title = switch (_registerStep) {
      _RegisterStep.email => 'Регистрация',
      _RegisterStep.code => 'Подтверждение почты',
      _RegisterStep.password => 'Пароль',
      _RegisterStep.profile => 'Профиль',
    };

    final body = switch (_registerStep) {
      _RegisterStep.email => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GlassInput(
            controller: _registerEmailController,
            hint: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _PrimaryButton(
            label: state.loading ? 'Отправка...' : 'Отправить код',
            onPressed: state.loading ? null : _handleRegisterEmail,
          ),
        ],
      ),
      _RegisterStep.code => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GlassInput(
            controller: _registerCodeController,
            hint: 'Код из письма',
            keyboardType: TextInputType.number,
          ),
          if (state.devCodeHint != null) ...[
            const SizedBox(height: 8),
            Text(
              'DEV CODE: ${state.devCodeHint}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _PrimaryButton(
            label: state.loading ? 'Проверка...' : 'Подтвердить код',
            onPressed: state.loading ? null : _handleRegisterCode,
          ),
        ],
      ),
      _RegisterStep.password => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GlassInput(
            controller: _registerPasswordController,
            hint: 'Пароль',
            obscure: true,
          ),
          const SizedBox(height: 12),
          _GlassInput(
            controller: _registerPasswordConfirmController,
            hint: 'Повторите пароль',
            obscure: true,
          ),
          const SizedBox(height: 14),
          _PrimaryButton(
            label: state.loading ? 'Сохраняем...' : 'Дальше',
            onPressed: state.loading ? null : _handleRegisterPassword,
          ),
        ],
      ),
      _RegisterStep.profile => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white12,
                  backgroundImage: _avatarBytes == null
                      ? null
                      : MemoryImage(_avatarBytes!),
                  child: _avatarBytes == null
                      ? const Icon(Icons.add_a_photo, color: Colors.white70)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Нажмите, чтобы загрузить аватар',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GlassInput(controller: _displayNameController, hint: 'Имя'),
          const SizedBox(height: 12),
          _GlassInput(
            controller: _usernameController,
            hint: 'Username (a-z0-9_)',
          ),
          const SizedBox(height: 12),
          _GlassInput(controller: _bioController, hint: 'Описание'),
          const SizedBox(height: 14),
          _PrimaryButton(
            label: state.loading
                ? 'Создаем аккаунт...'
                : 'Завершить регистрацию',
            onPressed: state.loading ? null : _handleRegisterProfile,
          ),
        ],
      ),
    };
    return _buildStepCardSwitcher(
      activeKey: stepKey,
      child: _AuthCardFrame(
        key: stepKey,
        title: title,
        subtitle: 'Шаг ${_registerStep.index + 1} из 4',
        child: body,
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Уже есть аккаунт?',
              style: TextStyle(color: Colors.white70),
            ),
            TextButton(
              onPressed: state.loading
                  ? null
                  : () {
                      setState(() {
                        _mode = _AuthMode.login;
                        _loginStep = _LoginStep.credentials;
                      });
                    },
              child: const Text('Войти'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.stateController;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
        final content = isDesktop
            ? Row(
                children: [
                  const Expanded(flex: 5, child: _LeftHero()),
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _mode == _AuthMode.login
                            ? _buildLoginCard(state)
                            : _buildRegisterCard(state),
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 16),
                  const SizedBox(height: 280, child: _LeftHero()),
                  const SizedBox(height: 24),
                  _mode == _AuthMode.login
                      ? _buildLoginCard(state)
                      : _buildRegisterCard(state),
                ],
              );
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0B0B0B),
                  Color(0xFF101010),
                  Color(0xFF090909),
                ],
              ),
            ),
            child: SafeArea(child: content),
          ),
        );
      },
    );
  }
}

class _LeftHero extends StatelessWidget {
  const _LeftHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _TypewriterHero(),
          const SizedBox(height: 20),
          Text(
            'ctrlchat',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypewriterHero extends StatefulWidget {
  const _TypewriterHero();

  @override
  State<_TypewriterHero> createState() => _TypewriterHeroState();
}

class _TypewriterHeroState extends State<_TypewriterHero> {
  static const _phrases = <String>[
    'chat',
    'безопасность',
    'конфиденциальность',
    'контролируй свою безопасность',
  ];

  String _displayText = '';
  int _phraseIndex = 0;
  int _charIndex = 0;
  bool _deleting = false;
  bool _showCursor = true;
  Timer? _cursorTimer;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showCursor = !_showCursor;
      });
    });
    _scheduleTick(const Duration(milliseconds: 240));
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _scheduleTick(Duration delay) {
    _typingTimer?.cancel();
    _typingTimer = Timer(delay, _tick);
  }

  void _tick() {
    if (!mounted) {
      return;
    }
    final target = _phrases[_phraseIndex];
    if (!_deleting) {
      if (_charIndex < target.length) {
        setState(() {
          _charIndex += 1;
          _displayText = target.substring(0, _charIndex);
        });
        _scheduleTick(const Duration(milliseconds: 80));
      } else {
        _scheduleTick(const Duration(milliseconds: 900));
        _deleting = true;
      }
      return;
    }

    if (_charIndex > 0) {
      setState(() {
        _charIndex -= 1;
        _displayText = target.substring(0, _charIndex);
      });
      _scheduleTick(const Duration(milliseconds: 50));
      return;
    }

    _deleting = false;
    _phraseIndex = (_phraseIndex + 1) % _phrases.length;
    _scheduleTick(const Duration(milliseconds: 220));
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white,
      fontSize: MediaQuery.sizeOf(context).width > 1320 ? 74 : 58,
      fontWeight: FontWeight.w700,
      height: 1.05,
      letterSpacing: 1.2,
    );

    return RichText(
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'ctrl\n'),
          TextSpan(text: _displayText),
          TextSpan(
            text: _showCursor ? '|' : ' ',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _AuthCardFrame extends StatelessWidget {
  const _AuthCardFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            child,
            const SizedBox(height: 14),
            const Divider(color: Colors.white24),
            footer,
          ],
        ),
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  const _GlassInput({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white70),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }
}
