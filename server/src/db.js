import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import Database from 'better-sqlite3';

import { config } from './config.js';
import { nowIso } from './utils/time.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const serverRoot = path.resolve(__dirname, '..');

const dataPath = path.resolve(serverRoot, config.dbPath);
fs.mkdirSync(path.dirname(dataPath), { recursive: true });

export const db = new Database(dataPath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  username TEXT UNIQUE,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  bio TEXT DEFAULT '',
  birth_date TEXT,
  password_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  last_seen_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_privacy (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  avatar_visibility TEXT NOT NULL DEFAULT 'everyone',
  bio_visibility TEXT NOT NULL DEFAULT 'everyone',
  last_seen_visibility TEXT NOT NULL DEFAULT 'contacts'
);

CREATE TABLE IF NOT EXISTS verification_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  purpose TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  payload TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_verification_email_purpose ON verification_codes(email, purpose);

CREATE TABLE IF NOT EXISTS registration_flows (
  token TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  code_verified_at TEXT NOT NULL,
  password_hash TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS login_challenges (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_hash TEXT NOT NULL,
  user_agent TEXT,
  ip TEXT,
  fingerprint TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);

CREATE TABLE IF NOT EXISTS user_keys (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  identity_public TEXT NOT NULL,
  signed_prekey_public TEXT NOT NULL,
  signed_prekey_signature TEXT NOT NULL,
  one_time_prekeys TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chats (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL DEFAULT 'direct',
  title TEXT,
  direct_key TEXT UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_members (
  chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member',
  muted INTEGER NOT NULL DEFAULT 0,
  pinned INTEGER NOT NULL DEFAULT 0,
  favorite INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plaintext TEXT,
  ciphertext TEXT,
  message_type TEXT NOT NULL DEFAULT 'text',
  reply_to_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
  edited_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON messages(chat_id, created_at DESC);

CREATE TABLE IF NOT EXISTS message_hidden (
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  hidden_at TEXT NOT NULL,
  PRIMARY KEY(message_id, user_id)
);

CREATE TABLE IF NOT EXISTS message_reactions (
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(message_id, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS call_logs (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  peer_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  direction TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT
);

CREATE TABLE IF NOT EXISTS sticker_packs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS stickers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pack_id INTEGER NOT NULL REFERENCES sticker_packs(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reporter_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  details TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TEXT NOT NULL,
  reviewed_at TEXT
);

CREATE TABLE IF NOT EXISTS bans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  ip TEXT,
  fingerprint TEXT,
  reason TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT
);
`);

export function selectUserPublic(userId) {
  return db
    .prepare(
      `SELECT id, email, username, display_name, avatar_url, bio, birth_date, status, last_seen_at, created_at, updated_at
       FROM users WHERE id = ?`,
    )
    .get(userId);
}

export function serializeUser(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    email: row.email,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    bio: row.bio,
    birthDate: row.birth_date,
    status: row.status,
    lastSeenAt: row.last_seen_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function allocateUserId() {
  const first = db.prepare('SELECT id FROM users ORDER BY id ASC LIMIT 1').get();
  if (!first) {
    return 1;
  }
  if (first.id > 1) {
    return 1;
  }
  const gap = db
    .prepare(
      `SELECT u1.id + 1 AS candidate
       FROM users u1
       LEFT JOIN users u2 ON u2.id = u1.id + 1
       WHERE u2.id IS NULL
       ORDER BY u1.id ASC
       LIMIT 1`,
    )
    .get();
  if (gap?.candidate) {
    return gap.candidate;
  }
  const maxId = db.prepare('SELECT MAX(id) AS max_id FROM users').get()?.max_id || 0;
  return maxId + 1;
}

export function bannedReason({ userId, ip, fingerprint }) {
  const now = nowIso();
  const byUser = userId
    ? db
        .prepare(
          `SELECT reason FROM bans
           WHERE user_id = ? AND (expires_at IS NULL OR expires_at > ?)
           ORDER BY created_at DESC LIMIT 1`,
        )
        .get(userId, now)
    : null;
  if (byUser) {
    return byUser.reason || 'Account is banned';
  }

  if (ip) {
    const byIp = db
      .prepare(
        `SELECT reason FROM bans
         WHERE ip = ? AND (expires_at IS NULL OR expires_at > ?)
         ORDER BY created_at DESC LIMIT 1`,
      )
      .get(ip, now);
    if (byIp) {
      return byIp.reason || 'IP is banned';
    }
  }

  if (fingerprint) {
    const byFp = db
      .prepare(
        `SELECT reason FROM bans
         WHERE fingerprint = ? AND (expires_at IS NULL OR expires_at > ?)
         ORDER BY created_at DESC LIMIT 1`,
      )
      .get(fingerprint, now);
    if (byFp) {
      return byFp.reason || 'Device fingerprint is banned';
    }
  }

  return null;
}
