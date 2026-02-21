import { randomUUID } from 'node:crypto';

import { Router } from 'express';
import { z } from 'zod';

import { db, selectUserPublic } from '../db.js';
import { authRequired } from '../services/auth.js';
import { createDirectChat, isUserInChat } from '../services/chats.js';
import { getIo } from '../services/socket.js';
import { nowIso } from '../utils/time.js';

export const chatRouter = Router();

chatRouter.get('/contacts', authRequired, (req, res) => {
  const q = String(req.query.q || '').trim();
  const sql = q
    ? `SELECT id, username, display_name, avatar_url, last_seen_at
       FROM users
       WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
       ORDER BY display_name ASC
       LIMIT 100`
    : `SELECT id, username, display_name, avatar_url, last_seen_at
       FROM users
       WHERE id != ?
       ORDER BY display_name ASC
       LIMIT 100`;
  const rows = q
    ? db.prepare(sql).all(req.auth.userId, `%${q}%`, `%${q}%`)
    : db.prepare(sql).all(req.auth.userId);
  res.json({
    contacts: rows.map((row) => ({
      id: row.id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      lastSeenAt: row.last_seen_at,
    })),
  });
});

chatRouter.post('/chats/direct', authRequired, (req, res) => {
  const schema = z.object({
    username: z.string().regex(/^[a-z0-9_]{4,24}$/),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid username' });
    return;
  }
  const username = parsed.data.username.toLowerCase();
  const target = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (!target) {
    res.status(404).json({ error: 'User not found' });
    return;
  }
  if (target.id === req.auth.userId) {
    res.status(400).json({ error: 'Cannot open chat with yourself' });
    return;
  }
  const chat = createDirectChat(req.auth.userId, target.id);
  res.json({ chatId: chat.id });
});

chatRouter.get('/chats', authRequired, (req, res) => {
  const tab = String(req.query.tab || 'home');
  if (tab === 'calls') {
    const calls = db
      .prepare(
        `SELECT c.id, c.peer_user_id, c.direction, c.status, c.started_at, c.ended_at,
                u.username AS peer_username, u.display_name AS peer_name, u.avatar_url AS peer_avatar
         FROM call_logs c
         LEFT JOIN users u ON u.id = c.peer_user_id
         WHERE c.user_id = ?
         ORDER BY c.started_at DESC LIMIT 100`,
      )
      .all(req.auth.userId);
    res.json({
      calls: calls.map((row) => ({
        id: row.id,
        peerUserId: row.peer_user_id,
        peerUsername: row.peer_username,
        peerName: row.peer_name,
        peerAvatar: row.peer_avatar,
        direction: row.direction,
        status: row.status,
        startedAt: row.started_at,
        endedAt: row.ended_at,
      })),
    });
    return;
  }

  const filterClause =
    tab === 'favorites'
      ? 'AND cm.favorite = 1 AND cm.archived = 0'
      : tab === 'archive'
        ? 'AND cm.archived = 1'
        : 'AND cm.archived = 0';

  const chats = db
    .prepare(
      `SELECT c.id, c.type, c.title, c.updated_at,
              cm.muted, cm.pinned, cm.favorite, cm.archived,
              m.id AS last_message_id, m.plaintext AS last_message_text, m.message_type AS last_message_type,
              m.created_at AS last_message_at, m.sender_id AS last_sender_id
       FROM chat_members cm
       JOIN chats c ON c.id = cm.chat_id
       LEFT JOIN messages m ON m.id = (
         SELECT mm.id FROM messages mm
         WHERE mm.chat_id = c.id
         ORDER BY mm.created_at DESC LIMIT 1
       )
       WHERE cm.user_id = ? ${filterClause}
       ORDER BY cm.pinned DESC, COALESCE(m.created_at, c.updated_at) DESC`,
    )
    .all(req.auth.userId);

  const mapped = chats.map((row) => {
    let peer = null;
    if (row.type === 'direct') {
      const peerRow = db
        .prepare(
          `SELECT u.id, u.username, u.display_name, u.avatar_url, u.last_seen_at
           FROM chat_members cm
           JOIN users u ON u.id = cm.user_id
           WHERE cm.chat_id = ? AND cm.user_id != ?`,
        )
        .get(row.id, req.auth.userId);
      if (peerRow) {
        peer = {
          id: peerRow.id,
          username: peerRow.username,
          displayName: peerRow.display_name,
          avatarUrl: peerRow.avatar_url,
          lastSeenAt: peerRow.last_seen_at,
        };
      }
    }

    return {
      id: row.id,
      type: row.type,
      title: row.type === 'direct' ? (peer?.displayName ?? 'Unknown') : row.title,
      updatedAt: row.updated_at,
      preferences: {
        muted: Boolean(row.muted),
        pinned: Boolean(row.pinned),
        favorite: Boolean(row.favorite),
        archived: Boolean(row.archived),
      },
      peer,
      lastMessage: row.last_message_id
        ? {
            id: row.last_message_id,
            text: row.last_message_text,
            type: row.last_message_type,
            createdAt: row.last_message_at,
            senderId: row.last_sender_id,
          }
        : null,
    };
  });

  res.json({ chats: mapped });
});

chatRouter.patch('/chats/:chatId/preferences', authRequired, (req, res) => {
  const schema = z.object({
    muted: z.boolean().optional(),
    pinned: z.boolean().optional(),
    favorite: z.boolean().optional(),
    archived: z.boolean().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const chatId = req.params.chatId;
  if (!isUserInChat(chatId, req.auth.userId)) {
    res.status(403).json({ error: 'No access to chat' });
    return;
  }
  const p = parsed.data;
  db.prepare(
    `UPDATE chat_members
     SET muted = COALESCE(?, muted),
         pinned = COALESCE(?, pinned),
         favorite = COALESCE(?, favorite),
         archived = COALESCE(?, archived)
     WHERE chat_id = ? AND user_id = ?`,
  ).run(
    p.muted == null ? null : Number(p.muted),
    p.pinned == null ? null : Number(p.pinned),
    p.favorite == null ? null : Number(p.favorite),
    p.archived == null ? null : Number(p.archived),
    chatId,
    req.auth.userId,
  );
  res.json({ ok: true });
});

chatRouter.get('/chats/:chatId/messages', authRequired, (req, res) => {
  const chatId = req.params.chatId;
  if (!isUserInChat(chatId, req.auth.userId)) {
    res.status(403).json({ error: 'No access to chat' });
    return;
  }
  const limit = Math.min(Math.max(Number(req.query.limit || 50), 1), 200);
  const before = String(req.query.before || '').trim();
  const rows = db
    .prepare(
      `SELECT m.*, u.username AS sender_username, u.display_name AS sender_name, u.avatar_url AS sender_avatar
       FROM messages m
       JOIN users u ON u.id = m.sender_id
       WHERE m.chat_id = ?
         AND m.id NOT IN (SELECT message_id FROM message_hidden WHERE user_id = ?)
         ${before ? 'AND m.created_at < ?' : ''}
       ORDER BY m.created_at DESC
       LIMIT ?`,
    )
    .all(...(before ? [chatId, req.auth.userId, before, limit] : [chatId, req.auth.userId, limit]));

  const ids = rows.map((row) => row.id);
  const reactionsByMessage = new Map();
  if (ids.length) {
    const placeholders = ids.map(() => '?').join(',');
    const reactions = db
      .prepare(
        `SELECT message_id, user_id, emoji
         FROM message_reactions
         WHERE message_id IN (${placeholders})`,
      )
      .all(...ids);
    for (const row of reactions) {
      if (!reactionsByMessage.has(row.message_id)) {
        reactionsByMessage.set(row.message_id, []);
      }
      reactionsByMessage.get(row.message_id).push({
        userId: row.user_id,
        emoji: row.emoji,
      });
    }
  }

  res.json({
    messages: rows
      .reverse()
      .map((row) => ({
        id: row.id,
        chatId: row.chat_id,
        senderId: row.sender_id,
        sender: {
          id: row.sender_id,
          username: row.sender_username,
          displayName: row.sender_name,
          avatarUrl: row.sender_avatar,
        },
        text: row.plaintext,
        ciphertext: row.ciphertext,
        type: row.message_type,
        replyToId: row.reply_to_id,
        editedAt: row.edited_at,
        createdAt: row.created_at,
        reactions: reactionsByMessage.get(row.id) || [],
      })),
  });
});

chatRouter.post('/chats/:chatId/messages', authRequired, (req, res) => {
  const schema = z.object({
    text: z.string().max(4000).optional(),
    ciphertext: z.string().max(32000).optional(),
    type: z.enum(['text', 'media', 'file', 'voice', 'video_note']).optional(),
    replyToId: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const chatId = req.params.chatId;
  if (!isUserInChat(chatId, req.auth.userId)) {
    res.status(403).json({ error: 'No access to chat' });
    return;
  }
  if (!parsed.data.text && !parsed.data.ciphertext) {
    res.status(400).json({ error: 'Message is empty' });
    return;
  }

  if (parsed.data.replyToId) {
    const replyExists = db
      .prepare('SELECT id FROM messages WHERE id = ? AND chat_id = ?')
      .get(parsed.data.replyToId, chatId);
    if (!replyExists) {
      res.status(400).json({ error: 'Reply message does not exist' });
      return;
    }
  }

  const id = randomUUID();
  const createdAt = nowIso();
  db.prepare(
    `INSERT INTO messages
     (id, chat_id, sender_id, plaintext, ciphertext, message_type, reply_to_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    id,
    chatId,
    req.auth.userId,
    parsed.data.text || null,
    parsed.data.ciphertext || null,
    parsed.data.type || 'text',
    parsed.data.replyToId || null,
    createdAt,
  );
  db.prepare('UPDATE chats SET updated_at = ? WHERE id = ?').run(createdAt, chatId);

  const sender = selectUserPublic(req.auth.userId);
  const message = {
    id,
    chatId,
    senderId: req.auth.userId,
    sender: {
      id: sender.id,
      username: sender.username,
      displayName: sender.display_name,
      avatarUrl: sender.avatar_url,
    },
    text: parsed.data.text || null,
    ciphertext: parsed.data.ciphertext || null,
    type: parsed.data.type || 'text',
    replyToId: parsed.data.replyToId || null,
    createdAt,
    editedAt: null,
    reactions: [],
  };
  const io = getIo();
  if (io) {
    io.to(`chat:${chatId}`).emit('message:new', message);
  }

  res.json({ message });
});

chatRouter.patch('/messages/:messageId', authRequired, (req, res) => {
  const schema = z.object({
    text: z.string().min(1).max(4000),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(req.params.messageId);
  if (!message) {
    res.status(404).json({ error: 'Message not found' });
    return;
  }
  if (message.sender_id !== req.auth.userId) {
    res.status(403).json({ error: 'Only sender can edit message' });
    return;
  }
  const editedAt = nowIso();
  db.prepare('UPDATE messages SET plaintext = ?, edited_at = ? WHERE id = ?').run(
    parsed.data.text,
    editedAt,
    req.params.messageId,
  );

  const io = getIo();
  if (io) {
    io.to(`chat:${message.chat_id}`).emit('message:edited', {
      messageId: message.id,
      chatId: message.chat_id,
      text: parsed.data.text,
      editedAt,
    });
  }

  res.json({ ok: true, editedAt });
});

chatRouter.delete('/messages/:messageId', authRequired, (req, res) => {
  const schema = z.object({
    scope: z.enum(['self', 'all']).default('self'),
  });
  const parsed = schema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(req.params.messageId);
  if (!message) {
    res.status(404).json({ error: 'Message not found' });
    return;
  }
  if (!isUserInChat(message.chat_id, req.auth.userId)) {
    res.status(403).json({ error: 'No access to chat' });
    return;
  }

  if (parsed.data.scope === 'self') {
    db.prepare(
      `INSERT INTO message_hidden (message_id, user_id, hidden_at)
       VALUES (?, ?, ?)
       ON CONFLICT(message_id, user_id) DO UPDATE SET hidden_at = excluded.hidden_at`,
    ).run(message.id, req.auth.userId, nowIso());
    res.json({ ok: true });
    return;
  }

  if (message.sender_id !== req.auth.userId) {
    res.status(403).json({ error: 'Only sender can delete for all' });
    return;
  }
  db.prepare('DELETE FROM messages WHERE id = ?').run(message.id);

  const io = getIo();
  if (io) {
    io.to(`chat:${message.chat_id}`).emit('message:deleted', {
      messageId: message.id,
      chatId: message.chat_id,
      scope: 'all',
    });
  }

  res.json({ ok: true });
});

chatRouter.post('/messages/:messageId/reactions', authRequired, (req, res) => {
  const schema = z.object({
    emoji: z.string().min(1).max(8),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const message = db.prepare('SELECT id, chat_id FROM messages WHERE id = ?').get(req.params.messageId);
  if (!message) {
    res.status(404).json({ error: 'Message not found' });
    return;
  }
  if (!isUserInChat(message.chat_id, req.auth.userId)) {
    res.status(403).json({ error: 'No access to chat' });
    return;
  }

  const exists = db
    .prepare('SELECT 1 FROM message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?')
    .get(message.id, req.auth.userId, parsed.data.emoji);
  let active;
  if (exists) {
    db.prepare('DELETE FROM message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?').run(
      message.id,
      req.auth.userId,
      parsed.data.emoji,
    );
    active = false;
  } else {
    db.prepare(
      'INSERT INTO message_reactions (message_id, user_id, emoji, created_at) VALUES (?, ?, ?, ?)',
    ).run(message.id, req.auth.userId, parsed.data.emoji, nowIso());
    active = true;
  }

  const io = getIo();
  if (io) {
    io.to(`chat:${message.chat_id}`).emit('message:reaction', {
      chatId: message.chat_id,
      messageId: message.id,
      userId: req.auth.userId,
      emoji: parsed.data.emoji,
      active,
    });
  }
  res.json({ ok: true, active });
});

chatRouter.get('/search', authRequired, (req, res) => {
  const q = String(req.query.q || '').trim();
  const scope = String(req.query.scope || 'messages');
  if (!q) {
    res.json({ results: [] });
    return;
  }

  if (scope === 'contacts') {
    const rows = db
      .prepare(
        `SELECT id, username, display_name, avatar_url
         FROM users
         WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
         ORDER BY display_name ASC LIMIT 100`,
      )
      .all(req.auth.userId, `%${q}%`, `%${q}%`);
    res.json({
      results: rows.map((row) => ({
        type: 'contact',
        id: row.id,
        username: row.username,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
      })),
    });
    return;
  }

  if (scope === 'chats') {
    const rows = db
      .prepare(
        `SELECT c.id, c.type, u.display_name AS peer_name, u.username AS peer_username, u.avatar_url AS peer_avatar
         FROM chat_members cm
         JOIN chats c ON c.id = cm.chat_id
         LEFT JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id != cm.user_id
         LEFT JOIN users u ON u.id = cm2.user_id
         WHERE cm.user_id = ? AND (u.display_name LIKE ? OR u.username LIKE ? OR c.title LIKE ?)
         GROUP BY c.id
         ORDER BY c.updated_at DESC LIMIT 100`,
      )
      .all(req.auth.userId, `%${q}%`, `%${q}%`, `%${q}%`);
    res.json({
      results: rows.map((row) => ({
        type: 'chat',
        id: row.id,
        chatType: row.type,
        title: row.peer_name || row.peer_username || 'Chat',
        avatarUrl: row.peer_avatar,
      })),
    });
    return;
  }

  if (scope === 'messages' || scope === 'multimedia' || scope === 'files') {
    const typeFilter =
      scope === 'multimedia'
        ? `AND m.message_type IN ('media', 'video_note', 'voice')`
        : scope === 'files'
          ? `AND m.message_type = 'file'`
          : '';
    const rows = db
      .prepare(
        `SELECT m.id, m.chat_id, m.sender_id, m.plaintext, m.message_type, m.created_at
         FROM messages m
         JOIN chat_members cm ON cm.chat_id = m.chat_id
         WHERE cm.user_id = ?
           AND m.plaintext LIKE ?
           ${typeFilter}
         ORDER BY m.created_at DESC LIMIT 200`,
      )
      .all(req.auth.userId, `%${q}%`);
    res.json({
      results: rows.map((row) => ({
        type: 'message',
        id: row.id,
        chatId: row.chat_id,
        senderId: row.sender_id,
        text: row.plaintext,
        messageType: row.message_type,
        createdAt: row.created_at,
      })),
    });
    return;
  }

  res.json({ results: [] });
});

chatRouter.get('/calls', authRequired, (req, res) => {
  const rows = db
    .prepare(
      `SELECT c.id, c.peer_user_id, c.direction, c.status, c.started_at, c.ended_at,
              u.username AS peer_username, u.display_name AS peer_name, u.avatar_url AS peer_avatar
       FROM call_logs c
       LEFT JOIN users u ON u.id = c.peer_user_id
       WHERE c.user_id = ?
       ORDER BY c.started_at DESC LIMIT 100`,
    )
    .all(req.auth.userId);
  res.json({
    calls: rows.map((row) => ({
      id: row.id,
      peerUserId: row.peer_user_id,
      peerUsername: row.peer_username,
      peerName: row.peer_name,
      peerAvatar: row.peer_avatar,
      direction: row.direction,
      status: row.status,
      startedAt: row.started_at,
      endedAt: row.ended_at,
    })),
  });
});

chatRouter.post('/calls/log', authRequired, (req, res) => {
  const schema = z.object({
    peerUserId: z.number().int().positive(),
    direction: z.enum(['incoming', 'outgoing']),
    status: z.enum(['missed', 'answered', 'declined']),
    startedAt: z.string().optional(),
    endedAt: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const id = randomUUID();
  db.prepare(
    `INSERT INTO call_logs (id, user_id, peer_user_id, direction, status, started_at, ended_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    id,
    req.auth.userId,
    parsed.data.peerUserId,
    parsed.data.direction,
    parsed.data.status,
    parsed.data.startedAt || nowIso(),
    parsed.data.endedAt || null,
  );
  res.json({ ok: true, id });
});
