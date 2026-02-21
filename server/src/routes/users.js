import argon2 from 'argon2';
import { Router } from 'express';
import { z } from 'zod';

import { db, serializeUser, selectUserPublic } from '../db.js';
import { authRequired } from '../services/auth.js';
import { nowIso } from '../utils/time.js';

export const usersRouter = Router();

usersRouter.get('/me', authRequired, (req, res) => {
  const privacy = db.prepare('SELECT * FROM user_privacy WHERE user_id = ?').get(req.auth.userId);
  res.json({
    user: serializeUser(req.auth.user),
    privacy: {
      avatarVisibility: privacy?.avatar_visibility || 'everyone',
      bioVisibility: privacy?.bio_visibility || 'everyone',
      lastSeenVisibility: privacy?.last_seen_visibility || 'contacts',
    },
  });
});

usersRouter.patch('/me', authRequired, (req, res) => {
  const schema = z.object({
    displayName: z.string().min(1).max(64).optional(),
    username: z.string().regex(/^[a-z0-9_]{4,24}$/).optional(),
    avatarUrl: z.string().url().optional().or(z.literal('')),
    bio: z.string().max(200).optional(),
    birthDate: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const payload = parsed.data;

  if (payload.username) {
    const username = payload.username.toLowerCase();
    const exists = db
      .prepare('SELECT id FROM users WHERE username = ? AND id != ?')
      .get(username, req.auth.userId);
    if (exists) {
      res.status(409).json({ error: 'Username is already taken' });
      return;
    }
    payload.username = username;
  }

  db.prepare(
    `UPDATE users
     SET display_name = COALESCE(?, display_name),
         username = COALESCE(?, username),
         avatar_url = CASE WHEN ? IS NULL THEN avatar_url ELSE ? END,
         bio = COALESCE(?, bio),
         birth_date = COALESCE(?, birth_date),
         updated_at = ?
     WHERE id = ?`,
  ).run(
    payload.displayName ?? null,
    payload.username ?? null,
    payload.avatarUrl ?? null,
    payload.avatarUrl || null,
    payload.bio ?? null,
    payload.birthDate ?? null,
    nowIso(),
    req.auth.userId,
  );

  const updated = selectUserPublic(req.auth.userId);
  res.json({ user: serializeUser(updated) });
});

usersRouter.patch('/me/privacy', authRequired, (req, res) => {
  const schema = z.object({
    avatarVisibility: z.enum(['everyone', 'contacts', 'nobody']).optional(),
    bioVisibility: z.enum(['everyone', 'contacts', 'nobody']).optional(),
    lastSeenVisibility: z.enum(['everyone', 'contacts', 'nobody']).optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const p = parsed.data;
  db.prepare(
    `INSERT INTO user_privacy (user_id, avatar_visibility, bio_visibility, last_seen_visibility)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       avatar_visibility = excluded.avatar_visibility,
       bio_visibility = excluded.bio_visibility,
       last_seen_visibility = excluded.last_seen_visibility`,
  ).run(
    req.auth.userId,
    p.avatarVisibility || 'everyone',
    p.bioVisibility || 'everyone',
    p.lastSeenVisibility || 'contacts',
  );
  res.json({ ok: true });
});

usersRouter.post('/me/change-password', authRequired, async (req, res) => {
  const schema = z.object({
    oldPassword: z.string().min(8).max(128),
    newPassword: z.string().min(8).max(128),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const current = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(req.auth.userId);
  const matches = await argon2.verify(current.password_hash, parsed.data.oldPassword);
  if (!matches) {
    res.status(401).json({ error: 'Old password is incorrect' });
    return;
  }
  const newHash = await argon2.hash(parsed.data.newPassword, { type: argon2.argon2id });
  db.prepare('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?').run(
    newHash,
    nowIso(),
    req.auth.userId,
  );
  res.json({ ok: true });
});

usersRouter.get('/me/sessions', authRequired, (req, res) => {
  const sessions = db
    .prepare(
      `SELECT id, user_agent, ip, fingerprint, created_at, expires_at, revoked_at
       FROM sessions WHERE user_id = ?
       ORDER BY created_at DESC`,
    )
    .all(req.auth.userId);
  res.json({
    sessions: sessions.map((row) => ({
      id: row.id,
      userAgent: row.user_agent,
      ip: row.ip,
      fingerprint: row.fingerprint,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
      revokedAt: row.revoked_at,
      current: row.id === req.auth.sessionId,
    })),
  });
});

usersRouter.delete('/me/sessions/:sessionId', authRequired, (req, res) => {
  db.prepare('UPDATE sessions SET revoked_at = ? WHERE id = ? AND user_id = ?').run(
    nowIso(),
    req.params.sessionId,
    req.auth.userId,
  );
  res.json({ ok: true });
});

usersRouter.get('/profile/:username', (req, res) => {
  const username = req.params.username.toLowerCase();
  const row = db
    .prepare(
      `SELECT id, username, display_name, avatar_url, bio, last_seen_at
       FROM users WHERE username = ?`,
    )
    .get(username);
  if (!row) {
    res.status(404).json({ error: 'User not found' });
    return;
  }
  res.json({
    user: {
      id: row.id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      bio: row.bio,
      lastSeenAt: row.last_seen_at,
    },
  });
});
