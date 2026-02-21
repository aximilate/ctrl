import 'package:flutter/material.dart';

import '../state/ctrlchat_state.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.stateController,
    required this.username,
  });

  final CtrlChatState stateController;
  final String username;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.stateController.getPublicProfile(widget.username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Профиль не найден',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            );
          }
          final user =
              (snapshot.data?['user'] ?? const <String, dynamic>{})
                  as Map<String, dynamic>;
          return Center(
            child: Container(
              width: 460,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.white12,
                    backgroundImage: user['avatarUrl'] == null
                        ? null
                        : NetworkImage(user['avatarUrl'] as String),
                    child: user['avatarUrl'] == null
                        ? const Icon(
                            Icons.person,
                            size: 38,
                            color: Colors.white70,
                          )
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (user['displayName'] ?? 'Unknown') as String,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${(user['username'] ?? '') as String}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (user['bio'] ?? '') as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xCCFFFFFF)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
