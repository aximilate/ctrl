import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/auth_page.dart';
import 'pages/messenger_page.dart';
import 'pages/profile_page.dart';
import 'state/ctrlchat_state.dart';

class CtrlChatAppRoot extends StatefulWidget {
  const CtrlChatAppRoot({super.key});

  @override
  State<CtrlChatAppRoot> createState() => _CtrlChatAppRootState();
}

class _CtrlChatAppRootState extends State<CtrlChatAppRoot> {
  late final CtrlChatState _state;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _state = CtrlChatState();
    _router = GoRouter(
      refreshListenable: _state,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => AuthPage(stateController: _state),
        ),
        GoRoute(
          path: '/app',
          builder: (context, state) => MessengerPage(stateController: _state),
        ),
        GoRoute(
          path: '/@:username',
          builder: (context, state) => ProfilePage(
            stateController: _state,
            username: state.pathParameters['username'] ?? '',
          ),
        ),
      ],
      redirect: (context, state) {
        if (!_state.initialized) {
          return state.matchedLocation == '/' ? null : '/';
        }
        final logged = _state.isAuthenticated;
        final location = state.matchedLocation;
        if (location.startsWith('/@')) {
          return null;
        }
        if (!logged && location != '/') {
          return '/';
        }
        if (logged && location == '/') {
          return '/app';
        }
        return null;
      },
    );

    _state.init();
  }

  @override
  void dispose() {
    _router.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFFF5F5F5);
    const bg = Color(0xFF0A0A0A);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'ctrlchat',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: const Color(0xFFE6E6E6),
          surface: const Color(0xFF111111),
          onSurface: textColor,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: textColor),
          bodyLarge: TextStyle(color: textColor),
          titleLarge: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ),
      routerConfig: _router,
    );
  }
}
