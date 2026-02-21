import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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
  final Map<int, List<_LocalStory>> _storiesByAccount =
      <int, List<_LocalStory>>{};
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
    _composerController.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _composerController.removeListener(_onComposerChanged);
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

  void _onComposerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
    Uint8List? memoryImage,
  }) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white12,
      backgroundImage: memoryImage != null
          ? MemoryImage(memoryImage)
          : imageUrl != null && imageUrl.isNotEmpty
          ? NetworkImage(imageUrl)
          : null,
      child: (memoryImage == null && (imageUrl == null || imageUrl.isEmpty))
          ? Text(
              fallback.isEmpty ? '?' : fallback.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            )
          : null,
    );
  }

  List<_LocalStory> _storiesForCurrentAccount(CtrlChatState state) {
    final userId = state.currentUser?.id;
    if (userId == null) {
      return const <_LocalStory>[];
    }
    return _storiesByAccount[userId] ?? const <_LocalStory>[];
  }

  Future<void> _pickStory(CtrlChatState state) async {
    final user = state.currentUser;
    if (user == null) {
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.media,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать выбранный файл')),
      );
      return;
    }
    final story = _LocalStory(
      ownerName: user.displayName,
      ownerAvatarUrl: user.avatarUrl,
      fileName: file.name,
    );
    setState(() {
      final mutable = List<_LocalStory>.from(
        _storiesByAccount[user.id] ?? const <_LocalStory>[],
      );
      mutable.insert(0, story);
      _storiesByAccount[user.id] = mutable;
      _storiesExpanded = true;
    });
  }

  Widget _buildStoriesPill(CtrlChatState state) {
    final stories = _storiesForCurrentAccount(state);
    final visible = stories.take(_storiesExpanded ? 5 : 3).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      width: 74,
      height: _storiesExpanded ? 236 : 74,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white24),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        child: !_storiesExpanded
            ? InkWell(
                key: const ValueKey('stories-collapsed'),
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  if (stories.isEmpty) {
                    _pickStory(state).catchError(_showError);
                    return;
                  }
                  setState(() {
                    _storiesExpanded = true;
                  });
                },
                child: Center(
                  child: stories.isEmpty
                      ? const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.add, color: Colors.black, size: 20),
                        )
                      : SizedBox(
                          width: 52,
                          height: 42,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: List.generate(visible.length, (index) {
                              final story = visible[index];
                              return Positioned(
                                left: index * 12.0,
                                top: index * 2.0,
                                child: _buildAvatar(
                                  imageUrl: story.ownerAvatarUrl,
                                  fallback: story.ownerName,
                                  radius: 14,
                                ),
                              );
                            }),
                          ),
                        ),
                ),
              )
            : Column(
                key: const ValueKey('stories-expanded'),
                children: [
                  IconButton(
                    onPressed: () => _pickStory(state).catchError(_showError),
                    icon: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.add, color: Colors.black, size: 16),
                    ),
                  ),
                  Expanded(
                    child: stories.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            itemCount: stories.length.clamp(0, 15),
                            itemBuilder: (context, index) {
                              final story = stories[index];
                              return Tooltip(
                                message: story.fileName,
                                child: _buildAvatar(
                                  imageUrl: story.ownerAvatarUrl,
                                  fallback: story.ownerName,
                                  radius: 14,
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                          ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _storiesExpanded = false;
                      });
                    },
                    icon: const Icon(Icons.expand_less_rounded, size: 20),
                    tooltip: 'Свернуть',
                  ),
                ],
              ),
      ),
    );
  }

  List<StoredAccount> _orderedAccounts(CtrlChatState state) {
    final activeId = state.currentUser?.id;
    final accounts = List<StoredAccount>.from(state.accounts);
    accounts.sort((a, b) {
      if (a.session.user.id == activeId) {
        return -1;
      }
      if (b.session.user.id == activeId) {
        return 1;
      }
      return 0;
    });
    return accounts;
  }

  Widget _buildAccountsPill(CtrlChatState state) {
    final accounts = _orderedAccounts(state);
    final visible = _accountsExpanded ? accounts : accounts.take(1).toList();
    final expandedHeight = 16 + (accounts.length + 1) * 52.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      width: 74,
      height: _accountsExpanded ? expandedHeight : 74,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white24),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_accountsExpanded)
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () async {
                  final allowed = await widget.stateController.canAddAccount();
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
            if (visible.isEmpty)
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
            ...visible.map((entry) {
              final user = entry.session.user;
              final active = state.currentUser?.id == user.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () async {
                    if (!_accountsExpanded) {
                      setState(() {
                        _accountsExpanded = true;
                      });
                      return;
                    }
                    if (active) {
                      setState(() {
                        _accountsExpanded = false;
                      });
                      return;
                    }
                    await widget.stateController.switchAccount(user.id);
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _accountsExpanded = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: active ? 40 : 36,
                    height: active ? 40 : 36,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white24,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? Colors.white : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        user.displayName.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: active ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
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
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        scale: selected ? 1.06 : 1,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
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
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Spacer(),
          _buildAccountsPill(state),
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
        return const _BlankPane();
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
        return const _BlankPane();
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
      return const _BlankPane();
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
    final isMedia = text.startsWith('[MEDIA] ');
    final isDocument = text.startsWith('[DOC] ');
    final isFile = text.startsWith('[FILE] ');
    final isAttachment = isMedia || isDocument || isFile;
    final attachmentName = isAttachment
        ? text.replaceFirst(RegExp(r'^\[[A-Z]+\]\s*'), '')
        : text;
    final isShort = attachmentName.length <= 45;
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
                      Flexible(
                        child: isAttachment
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isMedia
                                        ? Icons.perm_media_rounded
                                        : isDocument
                                        ? Icons.description_rounded
                                        : Icons.insert_drive_file_rounded,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(child: Text(attachmentName)),
                                ],
                              )
                            : Text(text),
                      ),
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
                      isAttachment
                          ? Row(
                              children: [
                                Icon(
                                  isMedia
                                      ? Icons.perm_media_rounded
                                      : isDocument
                                      ? Icons.description_rounded
                                      : Icons.insert_drive_file_rounded,
                                  size: 17,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: Text(attachmentName)),
                              ],
                            )
                          : Text(text),
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

  Future<void> _pickAndSendAttachment(String kind) async {
    if (widget.stateController.selectedChatId == null) {
      return;
    }
    FilePickerResult? picked;
    if (kind == 'media') {
      picked = await FilePicker.platform.pickFiles(type: FileType.media);
    } else if (kind == 'document') {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>[
          'pdf',
          'doc',
          'docx',
          'txt',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        ],
      );
    } else {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    }
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final fileName = picked.files.first.name.trim();
    if (fileName.isEmpty) {
      return;
    }
    try {
      await widget.stateController.sendAttachment(
        attachmentKind: kind,
        fileName: fileName,
      );
    } catch (error) {
      await _showError(error);
    }
  }

  Widget _buildChatPane(CtrlChatState state) {
    if (state.currentTab == CtrlTab.settings) {
      return _SettingsDetailPane(
        section: _settingsSection,
        stateController: widget.stateController,
      );
    }

    final chat = state.selectedChat;
    if (chat == null) {
      return const _BlankPane();
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
              PopupMenuButton<String>(
                tooltip: 'Прикрепить',
                icon: const Icon(Icons.attach_file_rounded),
                onSelected: (value) =>
                    _pickAndSendAttachment(value).catchError(_showError),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'media', child: Text('Мультимедиа')),
                  PopupMenuItem(value: 'document', child: Text('Документ')),
                  PopupMenuItem(value: 'file', child: Text('Файл')),
                ],
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.06, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(
                            '${state.currentTab.name}/${state.selectedChatId ?? 'none'}/$_settingsSection',
                          ),
                          child: _buildChatPane(state),
                        ),
                      ),
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
}

class _BlankPane extends StatelessWidget {
  const _BlankPane();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
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
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap('profile'),
          child: Container(
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

class _SettingsDetailPane extends StatefulWidget {
  const _SettingsDetailPane({
    required this.section,
    required this.stateController,
  });

  final String section;
  final CtrlChatState stateController;

  @override
  State<_SettingsDetailPane> createState() => _SettingsDetailPaneState();
}

class _SettingsDetailPaneState extends State<_SettingsDetailPane> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _newPasswordConfirmController = TextEditingController();
  bool _seeded = false;
  Uint8List? _avatarBytes;
  String _avatarVisibility = 'everyone';
  String _bioVisibility = 'everyone';
  String _lastSeenVisibility = 'contacts';
  String _language = 'ru';
  bool _notifyContacts = true;
  bool _notifyGroups = true;
  bool _notifyChannels = true;
  bool _notifyBots = true;

  CtrlChatState get _state => widget.stateController;

  @override
  void initState() {
    super.initState();
    _hydrateFromState(force: true);
  }

  @override
  void didUpdateWidget(covariant _SettingsDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateController.currentUser?.id !=
        widget.stateController.currentUser?.id) {
      _hydrateFromState(force: true);
    } else {
      _hydrateFromState();
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _birthDateController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _newPasswordConfirmController.dispose();
    super.dispose();
  }

  void _hydrateFromState({bool force = false}) {
    if (_seeded && !force) {
      return;
    }
    final user = _state.currentUser;
    _displayNameController.text = user?.displayName ?? '';
    _usernameController.text = user?.username ?? '';
    _bioController.text = user?.bio ?? '';
    _birthDateController.text = '';
    final privacy = _state.privacy;
    _avatarVisibility = privacy['avatarVisibility'] ?? 'everyone';
    _bioVisibility = privacy['bioVisibility'] ?? 'everyone';
    _lastSeenVisibility = privacy['lastSeenVisibility'] ?? 'contacts';
    _seeded = true;
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
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    setState(() {
      _avatarBytes = bytes;
    });
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _saveProfile() async {
    try {
      String? avatarUrl;
      if (_avatarBytes != null) {
        avatarUrl = 'data:image/png;base64,${base64Encode(_avatarBytes!)}';
      }
      await _state.updateProfile(
        displayName: _displayNameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
        bio: _bioController.text.trim(),
        birthDate: _birthDateController.text.trim().isEmpty
            ? null
            : _birthDateController.text.trim(),
        avatarUrl: avatarUrl,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarBytes = null;
      });
      _showInfo('Профиль сохранен');
    } catch (error) {
      _showInfo(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _savePrivacy() async {
    try {
      await _state.updatePrivacy(
        avatarVisibility: _avatarVisibility,
        bioVisibility: _bioVisibility,
        lastSeenVisibility: _lastSeenVisibility,
      );
      _showInfo('Настройки конфиденциальности сохранены');
    } catch (error) {
      _showInfo(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refreshSessions() async {
    try {
      await _state.loadSessions();
    } catch (error) {
      _showInfo(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    try {
      await _state.revokeSession(sessionId);
      _showInfo('Сеанс завершен');
    } catch (error) {
      _showInfo(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _savePassword() async {
    final oldPassword = _oldPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _newPasswordConfirmController.text;
    if (newPassword != confirmPassword) {
      _showInfo('Новый пароль и подтверждение не совпадают');
      return;
    }
    try {
      await _state.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _newPasswordConfirmController.clear();
      _showInfo('Пароль изменен');
    } catch (error) {
      _showInfo(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _buildProfileSection() {
    final user = _state.currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white12,
                backgroundImage: _avatarBytes != null
                    ? MemoryImage(_avatarBytes!)
                    : user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child:
                    (_avatarBytes == null &&
                        (user?.avatarUrl == null || user!.avatarUrl!.isEmpty))
                    ? Text(
                        (user?.displayName ?? 'U').characters.first
                            .toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Нажмите на аватар, чтобы заменить',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _state.loading
                  ? null
                  : () => _state.logoutActive().catchError((_) {}),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Выйти'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _LabeledInput(label: 'Имя', controller: _displayNameController),
        const SizedBox(height: 10),
        _LabeledInput(label: 'Username', controller: _usernameController),
        const SizedBox(height: 10),
        _LabeledInput(label: 'Описание', controller: _bioController),
        const SizedBox(height: 10),
        _LabeledInput(
          label: 'Дата рождения (YYYY-MM-DD)',
          controller: _birthDateController,
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: _state.loading ? null : _saveProfile,
          child: const Text('Сохранить профиль'),
        ),
      ],
    );
  }

  Widget _buildPrivacySection() {
    final variants = const <Map<String, String>>[
      {'id': 'everyone', 'title': 'Все'},
      {'id': 'contacts', 'title': 'Контакты'},
      {'id': 'nobody', 'title': 'Никто'},
    ];
    DropdownButtonFormField<String> dropdown(
      String label,
      String value,
      ValueChanged<String> onChanged,
    ) {
      return DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: variants
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry['id'],
                child: Text(entry['title'] ?? ''),
              ),
            )
            .toList(),
        onChanged: (next) {
          if (next == null) {
            return;
          }
          onChanged(next);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        dropdown('Кто видит аватар', _avatarVisibility, (value) {
          setState(() {
            _avatarVisibility = value;
          });
        }),
        const SizedBox(height: 10),
        dropdown('Кто видит описание', _bioVisibility, (value) {
          setState(() {
            _bioVisibility = value;
          });
        }),
        const SizedBox(height: 10),
        dropdown('Кто видит время захода', _lastSeenVisibility, (value) {
          setState(() {
            _lastSeenVisibility = value;
          });
        }),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: _state.loading ? null : _savePrivacy,
          child: const Text('Сохранить конфиденциальность'),
        ),
      ],
    );
  }

  Widget _buildSessionsSection() {
    final sessions = _state.sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _state.loading ? null : _refreshSessions,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Обновить'),
            ),
            const SizedBox(width: 10),
            Text(
              'Всего: ${sessions.length}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          const Text(
            'Нет данных о сессиях',
            style: TextStyle(color: Colors.white70),
          ),
        ...sessions.map((entry) {
          final current = entry['current'] == true;
          final revokedAt = entry['revokedAt'];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.devices_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((entry['userAgent'] ?? 'Unknown device').toString()),
                      const SizedBox(height: 2),
                      Text(
                        'IP: ${(entry['ip'] ?? '-').toString()}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (revokedAt != null)
                        const Text(
                          'Завершен',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (!current && revokedAt == null)
                  TextButton(
                    onPressed: _state.loading
                        ? null
                        : () => _revokeSession(
                            (entry['id'] ?? '').toString(),
                          ).catchError((_) {}),
                    child: const Text('Выкинуть'),
                  ),
                if (current)
                  const Text(
                    'Текущий',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLanguageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Русский'),
              selected: _language == 'ru',
              onSelected: (_) {
                setState(() {
                  _language = 'ru';
                });
              },
            ),
            ChoiceChip(
              label: const Text('English'),
              selected: _language == 'en',
              onSelected: (_) {
                setState(() {
                  _language = 'en';
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Язык применяется в клиенте мгновенно после полной локализации экранов.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildNotificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          value: _notifyContacts,
          onChanged: (value) {
            setState(() {
              _notifyContacts = value;
            });
          },
          title: const Text('Сообщения от контактов'),
        ),
        SwitchListTile.adaptive(
          value: _notifyGroups,
          onChanged: (value) {
            setState(() {
              _notifyGroups = value;
            });
          },
          title: const Text('Сообщения от групп'),
        ),
        SwitchListTile.adaptive(
          value: _notifyChannels,
          onChanged: (value) {
            setState(() {
              _notifyChannels = value;
            });
          },
          title: const Text('Сообщения от каналов'),
        ),
        SwitchListTile.adaptive(
          value: _notifyBots,
          onChanged: (value) {
            setState(() {
              _notifyBots = value;
            });
          },
          title: const Text('Сообщения от ботов'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _showInfo(
            'Разрешение на браузерные уведомления запроси в настройках сайта браузера',
          ),
          child: const Text('Разрешение браузера'),
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabeledInput(
          label: 'Старый пароль',
          controller: _oldPasswordController,
          obscure: true,
        ),
        const SizedBox(height: 10),
        _LabeledInput(
          label: 'Новый пароль',
          controller: _newPasswordController,
          obscure: true,
        ),
        const SizedBox(height: 10),
        _LabeledInput(
          label: 'Повторите новый пароль',
          controller: _newPasswordConfirmController,
          obscure: true,
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: _state.loading ? null : _savePassword,
          child: const Text('Сменить пароль'),
        ),
        const SizedBox(height: 16),
        Text(
          'Текущая почта: ${_state.currentUser?.email ?? '-'}',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      'profile' => 'Профиль',
      'privacy' => 'Конфиденциальность',
      'sessions' => 'Активные сеансы',
      'language' => 'Язык',
      'notifications' => 'Уведомления и звуки',
      'security' => 'Смена пароля и почты',
      _ => 'Настройки',
    };
    final body = switch (widget.section) {
      'profile' => _buildProfileSection(),
      'privacy' => _buildPrivacySection(),
      'sessions' => _buildSessionsSection(),
      'language' => _buildLanguageSection(),
      'notifications' => _buildNotificationSection(),
      'security' => _buildSecuritySection(),
      _ => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_state.loading)
                const CircularProgressIndicator(strokeWidth: 2),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(key: ValueKey(widget.section), child: body),
          ),
        ],
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _LocalStory {
  const _LocalStory({
    required this.ownerName,
    required this.ownerAvatarUrl,
    required this.fileName,
  });

  final String ownerName;
  final String? ownerAvatarUrl;
  final String fileName;
}
