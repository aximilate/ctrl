import { randomUUID } from 'node:crypto';

import { db } from '../db.js';
import { nowIso } from '../utils/time.js';

export function createDirectChat(userA, userB) {
  const [low, high] = [Math.min(userA, userB), Math.max(userA, userB)];
  const directKey = `${low}:${high}`;
  const existing = db.prepare('SELECT * FROM chats WHERE direct_key = ?').get(directKey);
  if (existing) {
    return existing;
  }

  const chatId = randomUUID();
  const timestamp = nowIso();
  db.prepare(
    `INSERT INTO chats (id, type, title, direct_key, created_at, updated_at)
     VALUES (?, 'direct', NULL, ?, ?, ?)`,
  ).run(chatId, directKey, timestamp, timestamp);
  db.prepare('INSERT INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, low);
  db.prepare('INSERT INTO chat_members (chat_id, user_id) VALUES (?, ?)').run(chatId, high);
  return db.prepare('SELECT * FROM chats WHERE id = ?').get(chatId);
}

export function isUserInChat(chatId, userId) {
  const row = db
    .prepare('SELECT 1 AS ok FROM chat_members WHERE chat_id = ? AND user_id = ?')
    .get(chatId, userId);
  return Boolean(row?.ok);
}
