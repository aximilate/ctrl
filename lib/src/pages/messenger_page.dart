import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/entities.dart';
import '../state/ctrlchat_state.dart';

class MessengerPage extends StatefulWidget {
  const MessengerPage({super.key, required this.stateController});

  final CtrlChatState stateController;

  @override
  State<MessengerPage> createState() => _MessengerPageState();
}

class _MessengerPageState extends State<MessengerPage> {
  final _searchController = TextEditingController();
  final _composerController = TextEditingController();
  Timer? _searchDebounce;
  bool _storiesExpanded = false;
  bool _accountsExpanded = false;
  String _searchScope = 'messages';
  String _settingsSection = 'profile';

  static const _searchScopes = <String>[
    'chats',
    'channels',
    'bots',
    'messages',
    'multimedia',
    'files',
  ];

  static const _reactionPalette = <String>[
    '\u{1F44D}',
    '\u{2764}\u{FE0F}',
    '\u{1F525}',
    '\u{1F602}',
    '\u{1F622}',
    '\u{1F44F}',
    '\u{1F91D}',
    '\u{1F621}',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _composerController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      widget.stateController.search(
        query: _searchController.text,
        scope: _searchScope,
      );
    });
  }

  Future<void> _showError(Object error) async {
    if (!mounted) {
      return;
    }
    final message = error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildAvatar({
    String? imageUrl,
    required String fallback,
    double radius = 18,
  }) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white12,
      backgroundImage: imageUrl != null && imageUrl.isNotEmpty
          ? NetworkImage(imageUrl)
          : null,
      child: imageUrl == null || imageUrl.isEmpty
          ? Text(
              fallback.isEmpty ? '?' : fallback.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            )
          : null,
    );
  }

  Widget _buildStoriesPill(CtrlChatState state) {
    final chatsWithPeers = state.chats
        .where((chat) => chat.peer != null)
        .toList();
    final avatarCount = _storiesExpanded ? 5 : 3;
    final visible = chatsWithPeers.take(avatarCount).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _storiesExpanded = !_storiesExpanded;
          });
        },
        borderRadius: BorderRadius.circular(24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: !_storiesExpanded
              ? SizedBox(
                  key: const ValueKey('stories-collapsed'),
                  height: 46,
                  child: Stack(
                    children: List.generate(
                      visible.length,
                      (index) => Positioned(
                        left: index * 16.0,
                        top: 4,
                        child: _buildAvatar(
                          imageUrl: visible[index].peer?.avatarUrl,
                          fallback: visible[index].peer?.displayName ?? 'S',
                          radius: 14,
                        ),
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  key: const ValueKey('stories-expanded'),
                  height: 210,
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.add, color: Colors.black, size: 17),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: chatsWithPeers.length.clamp(0, 5),
                          itemBuilder: (context, index) {
                            final chat = chatsWithPeers[index];
                            return _buildAvatar(
                              imageUrl: chat.peer?.avatarUrl,
                              fallback: chat.peer?.displayName ?? 'S',
                              radius: 14,
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLeftRail(CtrlChatState state) {
    final tabIconMap = <CtrlTab, IconData>{
      CtrlTab.home: Icons.home_rounded,
      CtrlTab.favorites: Icons.star_rounded,
      CtrlTab.contacts: Icons.person_rounded,
      CtrlTab.calls: Icons.call_rounded,
      CtrlTab.settings: Icons.settings_rounded,
    };

    return SizedBox(
      width: 96,
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildStoriesPill(state),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              child: Column(
                children: tabIconMap.entries.map((entry) {
                  final selected = state.currentTab == entry.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () {
                        widget.stateController.loadTab(entry.key);
                      },
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Icon(
                          entry.value,
                          color: selected ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            width: 74,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_accountsExpanded)
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () async {
                      final allowed = await widget.stateController
                          .canAddAccount();
                      if (!mounted) {
                        return;
                      }
                      if (!allowed) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Можно добавить максимум 3 аккаунта'),
                          ),
                        );
                        return;
                      }
                      context.go('/');
                    },
                  ),
                ...state.accounts.map((entry) {
                  final user = entry.session.user;
                  final active = state.currentUser?.id == user.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () =>
                          widget.stateController.switchAccount(user.id),
                      child: CircleAvatar(
                        radius: active ? 19 : 17,
                        backgroundColor: active ? Colors.white : Colors.white24,
                        child: Text(
                          user.displayName.characters.first.toUpperCase(),
                          style: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _accountsExpanded = !_accountsExpanded;
                    });
                  },
                  child: _buildAvatar(
                    imageUrl: state.currentUser?.avatarUrl,
                    fallback: state.currentUser?.displayName ?? 'U',
                    radius: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildSearchBar(CtrlChatState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Поиск',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_searchController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final scope = _searchScopes[index];
                final selected = _searchScope == scope;
                return ChoiceChip(
                  selected: selected,
                  label: Text(scope),
                  onSelected: (_) {
                    setState(() {
                      _searchScope = scope;
                    });
                    widget.stateController.search(
                      query: _searchController.text,
                      scope: scope,
                    );
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _searchScopes.length,
            ),
          ),
        ],
      ],
    );
  }

  String _emptyLabelForTab(CtrlTab tab) {
    return switch (tab) {
      CtrlTab.home => 'Чатов пока нет :(',
      CtrlTab.favorites => 'Избранных контактов пока нет :(',
      CtrlTab.contacts => 'Контактов пока нет :(',
      CtrlTab.calls => 'Звонков пока нет :(',
      CtrlTab.settings => 'Настроек пока нет :(',
    };
  }

  Future<void> _showChatContextMenu(
    BuildContext context,
    Offset position,
    ChatItem chat,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'mute',
          child: Text(
            chat.preferences.muted ? 'Включить звук' : 'Отключить звук',
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Text(chat.preferences.pinned ? 'Открепить' : 'Закрепить'),
        ),
        const PopupMenuItem(value: 'archive', child: Text('Архивировать')),
      ],
    );
    if (selected == null) {
      return;
    }
    switch (selected) {
      case 'mute':
        await widget.stateController.updateChatPreferences(
          chat.id,
          muted: !chat.preferences.muted,
        );
      case 'pin':
        await widget.stateController.updateChatPreferences(
          chat.id,
          pinned: !chat.preferences.pinned,
        );
      case 'archive':
        await widget.stateController.updateChatPreferences(
          chat.id,
          archived: true,
        );
    }
  }

  Widget _buildChatList(CtrlChatState state) {
    if (state.voiceHoldMode) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(22, (index) {
                  final height = 12.0 + (index % 5) * 8.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300 + index * 12),
                      width: 3,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Идет запись голосового сообщения...'),
          ],
        ),
      );
    }

    if (_searchController.text.trim().isNotEmpty) {
      final results = state.searchResults;
      if (results.isEmpty) {
        return const Center(
          child: Text(
            'Ничего не найдено',
            style: TextStyle(color: Colors.white70),
          ),
        );
      }
      return ListView.separated(
        itemCount: results.length,
        separatorBuilder: (_, __) =>
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        itemBuilder: (context, index) {
          final row = results[index];
          return ListTile(
            title: Text(
              (row['title'] ?? row['displayName'] ?? row['text'] ?? 'Result')
                  as String,
            ),
            subtitle: Text((row['type'] ?? '') as String),
            onTap: () async {
              if (row['chatId'] != null) {
                await widget.stateController.openChat(row['chatId'] as String);
              }
            },
          );
        },
      );
    }

    if (state.currentTab == CtrlTab.contacts) {
      if (state.contacts.isEmpty) {
        return _EmptyPane(label: _emptyLabelForTab(state.currentTab));
      }
      return ListView.separated(
        itemCount: state.contacts.length,
        separatorBuilder: (_, __) =>
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        itemBuilder: (context, index) {
          final contact = state.contacts[index];
          return ListTile(
            leading: _buildAvatar(
              imageUrl: contact.avatarUrl,
              fallback: contact.displayName,
            ),
            title: Text(contact.displayName),
            subtitle: Text('@${contact.username ?? 'unknown'}'),
            onTap: () async {
              try {
                await widget.stateController.openDirectChatByUsername(
                  contact.username ?? '',
                );
              } catch (error) {
                await _showError(error);
              }
            },
          );
        },
      );
    }

    if (state.currentTab == CtrlTab.calls) {
      if (state.calls.isEmpty) {
        return _EmptyPane(label: _emptyLabelForTab(state.currentTab));
      }
      return ListView.builder(
        itemCount: state.calls.length,
        itemBuilder: (context, index) {
          final call = state.calls[index];
          return ListTile(
            leading: _buildAvatar(
              imageUrl: call.peerAvatar,
              fallback: call.peerName ?? 'U',
            ),
            title: Text(call.peerName ?? '@${call.peerUsername ?? 'unknown'}'),
            subtitle: Text('${call.direction} • ${call.status}'),
            trailing: Text(
              DateFormat(
                'dd.MM HH:mm',
              ).format(DateTime.tryParse(call.startedAt) ?? DateTime.now()),
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          );
        },
      );
    }

    if (state.currentTab == CtrlTab.settings) {
      return _SettingsList(
        user: state.currentUser,
        selected: _settingsSection,
        onTap: (value) {
          setState(() {
            _settingsSection = value;
          });
        },
      );
    }

    if (state.chats.isEmpty) {
      return _EmptyPane(label: _emptyLabelForTab(state.currentTab));
    }

    return ListView.separated(
      itemCount: state.chats.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
      itemBuilder: (context, index) {
        final chat = state.chats[index];
        final selected = state.selectedChatId == chat.id;
        return GestureDetector(
          onSecondaryTapDown: (details) {
            _showChatContextMenu(context, details.globalPosition, chat);
          },
          child: InkWell(
            onTap: () => widget.stateController.openChat(chat.id),
            child: Container(
              color: selected
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _buildAvatar(
                    imageUrl: chat.peer?.avatarUrl,
                    fallback: chat.title,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (chat.preferences.pinned)
                              const Icon(Icons.push_pin, size: 14),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          chat.lastMessage?.text ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMessageContextMenu(
    BuildContext context,
    Offset position,
    ChatMessage message,
    bool isMine,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        ..._reactionPalette.map(
          (emoji) => PopupMenuItem(value: 'react:$emoji', child: Text(emoji)),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'reply', child: Text('Ответить')),
        const PopupMenuItem(value: 'copy', child: Text('Скопировать текст')),
        const PopupMenuItem(value: 'forward', child: Text('Переслать')),
        const PopupMenuItem(value: 'delete', child: Text('Удалить')),
        if (isMine) const PopupMenuItem(value: 'edit', child: Text('Изменить')),
        if (!isMine)
          const PopupMenuItem(value: 'report', child: Text('Пожаловаться')),
      ],
    );

    if (selected == null) {
      return;
    }
    if (selected.startsWith('react:')) {
      final emoji = selected.split(':').last;
      await widget.stateController.reactToMessage(
        messageId: message.id,
        emoji: emoji,
      );
      return;
    }
    switch (selected) {
      case 'reply':
        widget.stateController.setReplyTo(message.id);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text ?? ''));
      case 'forward':
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Форвард будет подключен на следующем этапе'),
          ),
        );
      case 'delete':
        final scope = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить сообщение'),
            content: const Text('Выберите вариант удаления'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('self'),
                child: const Text('Удалить у себя'),
              ),
              TextButton(
                onPressed: isMine
                    ? () => Navigator.of(context).pop('all')
                    : null,
                child: const Text('Удалить у всех'),
              ),
            ],
          ),
        );
        if (scope != null) {
          await widget.stateController.deleteMessage(
            messageId: message.id,
            scope: scope,
          );
        }
      case 'edit':
        final controller = TextEditingController(text: message.text ?? '');
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Изменить сообщение'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Сохранить'),
              ),
            ],
          ),
        );
        if (result != null && result.isNotEmpty) {
          await widget.stateController.editMessage(
            messageId: message.id,
            text: result,
          );
        }
      case 'report':
        final reasons = ['Спам', 'Оскорбление', 'Мошенничество', 'Другое'];
        String reason = reasons.first;
        final detailsController = TextEditingController();
        final submit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Пожаловаться'),
            content: StatefulBuilder(
              builder: (context, setStateDialog) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: reason,
                      items: reasons
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry,
                              child: Text(entry),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setStateDialog(() {
                          reason = value;
                        });
                      },
                    ),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Опишите причину',
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Отправить'),
              ),
            ],
          ),
        );
        if (submit == true) {
          await widget.stateController.report(
            reason: reason,
            details: detailsController.text.trim(),
            targetUserId: message.senderId,
            messageId: message.id,
          );
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Жалоба отправлена')));
        }
    }
  }

  Widget _buildMessageBubble(CtrlChatState state, ChatMessage message) {
    final mine = message.senderId == state.currentUser?.id;
    final text = message.text ?? message.ciphertext ?? '';
    final isShort = text.length <= 45;
    final created = DateTime.tryParse(message.createdAt);
    final time = DateFormat('HH:mm').format(created ?? DateTime.now());

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showMessageContextMenu(
            context,
            details.globalPosition,
            message,
            mine,
          ).catchError(_showError);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.replyToId != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(width: 3, height: 30, color: Colors.white70),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Ответ на сообщение',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isShort)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(child: Text(text)),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                          if (message.editedAt != null)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.edit,
                                size: 12,
                                color: Colors.white60,
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              time,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white60,
                              ),
                            ),
                            if (message.editedAt != null)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: Colors.white60,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: message.reactions
                        .map(
                          (reaction) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              reaction.emoji,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEmojiStickerDialog() async {
    final stickerPacks = await widget.stateController.getStickerPacks();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        final emoji = List<String>.generate(
          160,
          (index) => String.fromCharCode(0x1F600 + (index % 80)),
        );
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: const TabBar(
              tabs: [
                Tab(text: 'Эмодзи'),
                Tab(text: 'Фото'),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 380,
              child: TabBarView(
                children: [
                  GridView.builder(
                    itemCount: emoji.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                        ),
                    itemBuilder: (context, index) {
                      return InkWell(
                        onTap: () {
                          _composerController.text += emoji[index];
                          Navigator.of(context).pop();
                        },
                        child: Center(
                          child: Text(
                            emoji[index],
                            style: const TextStyle(fontSize: 23),
                          ),
                        ),
                      );
                    },
                  ),
                  Column(
                    children: [
                      Expanded(
                        child: stickerPacks.isEmpty
                            ? const Center(child: Text('Стикерпаков пока нет'))
                            : ListView.builder(
                                itemCount: stickerPacks.length,
                                itemBuilder: (context, index) {
                                  final pack = stickerPacks[index];
                                  return ListTile(
                                    title: Text(
                                      (pack['title'] ?? 'pack') as String,
                                    ),
                                    subtitle: Text('ID: ${(pack['id'] ?? 0)}'),
                                  );
                                },
                              ),
                      ),
                      const Divider(),
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () async {
                                final controller = TextEditingController();
                                final name = await showDialog<String>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Новый стикерпак'),
                                    content: TextField(
                                      controller: controller,
                                      decoration: const InputDecoration(
                                        hintText: 'Название',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text('Отмена'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.of(
                                          context,
                                        ).pop(controller.text.trim()),
                                        child: const Text('Создать'),
                                      ),
                                    ],
                                  ),
                                );
                                if (name != null && name.isNotEmpty) {
                                  await widget.stateController
                                      .createStickerPack(name);
                                  if (!mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                            ...stickerPacks
                                .take(8)
                                .map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: CircleAvatar(
                                      backgroundColor: Colors.white12,
                                      child: Text(
                                        (entry['title'] ?? '?')
                                            .toString()
                                            .characters
                                            .first
                                            .toUpperCase(),
                                      ),
                                    ),
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
  }

  Widget _buildChatPane(CtrlChatState state) {
    if (state.currentTab == CtrlTab.settings) {
      return _SettingsDetailPane(
        section: _settingsSection,
        user: state.currentUser,
        apiBase: state.apiBaseUrl,
      );
    }

    final chat = state.selectedChat;
    if (chat == null) {
      return _EmptyPane(
        label: state.currentTab == CtrlTab.contacts
            ? 'Выберите контакт'
            : state.currentTab == CtrlTab.calls
            ? 'История звонков'
            : 'Выберите чат',
      );
    }

    final messages = state.selectedMessages;
    final replyTo = state.replyToMessageId;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
          ),
          child: Row(
            children: [
              _buildAvatar(
                imageUrl: chat.peer?.avatarUrl,
                fallback: chat.title,
                radius: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      chat.peer?.lastSeenAt != null
                          ? 'был(а) в сети ${chat.peer?.lastSeenAt}'
                          : 'в сети',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Поиск сообщений',
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.call_rounded),
                tooltip: 'Позвонить',
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D0D0D), Color(0xFF101010)],
              ),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: messages.length,
              itemBuilder: (context, index) =>
                  _buildMessageBubble(state, messages[index]),
            ),
          ),
        ),
        if (replyTo != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ответ на сообщение $replyTo',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => widget.stateController.setReplyTo(null),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file_rounded),
                onPressed: () async {
                  final selected = await showMenu<String>(
                    context: context,
                    position: const RelativeRect.fromLTRB(30, 30, 0, 0),
                    items: const [
                      PopupMenuItem(value: 'media', child: Text('Мультимедиа')),
                      PopupMenuItem(value: 'document', child: Text('Документ')),
                      PopupMenuItem(value: 'file', child: Text('Файл')),
                    ],
                  );
                  if (!mounted || selected == null) {
                    return;
                  }
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Выбрано: $selected')));
                },
              ),
              Expanded(
                child: TextField(
                  controller: _composerController,
                  minLines: 1,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: 'Введите сообщение',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _openEmojiStickerDialog,
                icon: const Icon(Icons.emoji_emotions_outlined),
              ),
              GestureDetector(
                onLongPressStart: (_) =>
                    widget.stateController.setVoiceHoldMode(true),
                onLongPressEnd: (_) {
                  widget.stateController.setVoiceHoldMode(false);
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Голосовое сообщение записано (демо)'),
                    ),
                  );
                },
                child: IconButton(
                  onPressed: () async {
                    if (_composerController.text.trim().isNotEmpty) {
                      try {
                        await widget.stateController.sendMessage(
                          _composerController.text,
                        );
                        _composerController.clear();
                      } catch (error) {
                        await _showError(error);
                      }
                      return;
                    }
                    widget.stateController.toggleVideoNoteMode();
                  },
                  icon: Icon(
                    _composerController.text.trim().isNotEmpty
                        ? Icons.send_rounded
                        : state.videoNoteMode
                        ? Icons.radio_button_checked
                        : Icons.mic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.stateController;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        if (!state.isAuthenticated) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final width = MediaQuery.sizeOf(context).width;
        if (width < 980) {
          return const Scaffold(
            body: Center(child: Text('Desktop layout only')),
          );
        }

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF080808), Color(0xFF101010)],
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  _buildLeftRail(state),
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                            child: _buildSearchBar(state),
                          ),
                          Expanded(child: _buildChatList(state)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 14, 12, 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: _buildChatPane(state),
                    ),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            onPressed: () => widget.stateController.logoutActive(),
            label: const Text('Выйти'),
            icon: const Icon(Icons.logout),
          ),
        );
      },
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sentiment_dissatisfied_rounded,
            size: 82,
            color: Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final AuthUser? user;
  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final entries = <Map<String, String>>[
      {'id': 'profile', 'title': 'Профиль'},
      {'id': 'privacy', 'title': 'Конфиденциальность'},
      {'id': 'sessions', 'title': 'Активные сеансы'},
      {'id': 'language', 'title': 'Язык'},
      {'id': 'notifications', 'title': 'Уведомления и звуки'},
      {'id': 'security', 'title': 'Смена пароля/почты'},
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Text(
                  user?.displayName.characters.first.toUpperCase() ?? 'U',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '@${user?.username ?? 'unknown'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...entries.map((entry) {
          final isSelected = selected == entry['id'];
          return ListTile(
            selected: isSelected,
            selectedTileColor: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: Text(entry['title']!),
            onTap: () => onTap(entry['id']!),
          );
        }),
      ],
    );
  }
}

class _SettingsDetailPane extends StatelessWidget {
  const _SettingsDetailPane({
    required this.section,
    required this.user,
    required this.apiBase,
  });

  final String section;
  final AuthUser? user;
  final String apiBase;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      'profile' => 'Профиль',
      'privacy' => 'Конфиденциальность',
      'sessions' => 'Активные сеансы',
      'language' => 'Язык',
      'notifications' => 'Уведомления и звуки',
      'security' => 'Смена пароля и почты',
      _ => 'Настройки',
    };

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (section == 'profile') ...[
            const _SettingField(
              label: 'Имя',
              value: 'Можно изменить в этом блоке',
            ),
            _SettingField(
              label: 'Текущий username',
              value: '@${user?.username ?? 'unknown'}',
            ),
            const _SettingField(
              label: 'Описание',
              value: 'Добавьте публичное описание профиля',
            ),
            const _SettingField(
              label: 'Дата рождения',
              value: 'Можно добавить в профиле',
            ),
          ],
          if (section == 'privacy') ...[
            const _SettingField(
              label: 'Аватарка',
              value: 'Видно: всем / контактам / никому',
            ),
            const _SettingField(
              label: 'Описание',
              value: 'Видно: всем / контактам / никому',
            ),
            const _SettingField(
              label: 'Время захода',
              value: 'Видно: всем / контактам / никому',
            ),
          ],
          if (section == 'sessions') ...[
            const _SettingField(
              label: 'Устройства',
              value: 'Показываются в API /users/me/sessions',
            ),
            const _SettingField(
              label: 'IP',
              value: 'Есть возможность завершать сессии',
            ),
          ],
          if (section == 'language') ...[
            const _SettingField(label: 'Русский', value: 'Доступен'),
            const _SettingField(label: 'English', value: 'Available'),
          ],
          if (section == 'notifications') ...[
            const _SettingField(
              label: 'Контакты',
              value: 'Вкл/выкл + исключения',
            ),
            const _SettingField(
              label: 'Группы/каналы/боты',
              value: 'Вкл/выкл + исключения',
            ),
            const _SettingField(
              label: 'Браузерные уведомления',
              value: 'Запрос разрешения',
            ),
          ],
          if (section == 'security') ...[
            const _SettingField(
              label: 'Пароль',
              value: 'Изменение через API /users/me/change-password',
            ),
            const _SettingField(
              label: 'Почта',
              value: 'Добавляется в следующем релизе',
            ),
            _SettingField(label: 'API', value: apiBase),
          ],
        ],
      ),
    );
  }
}

class _SettingField extends StatelessWidget {
  const _SettingField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
