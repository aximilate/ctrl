import { promisify } from 'node:util';
import { exec as execCb } from 'node:child_process';

import { Router } from 'express';
import { z } from 'zod';

import { config } from '../config.js';
import { db } from '../db.js';
import { adminRequired } from '../services/auth.js';
import { nowIso } from '../utils/time.js';

const exec = promisify(execCb);

export const adminRouter = Router();

adminRouter.get('/overview', adminRequired, (_req, res) => {
  const users = db.prepare('SELECT COUNT(*) AS c FROM users').get().c;
  const chats = db.prepare('SELECT COUNT(*) AS c FROM chats').get().c;
  const messages = db.prepare('SELECT COUNT(*) AS c FROM messages').get().c;
  const openReports = db.prepare(`SELECT COUNT(*) AS c FROM reports WHERE status = 'open'`).get().c;
  res.json({ users, chats, messages, openReports });
});

adminRouter.get('/reports', adminRequired, (_req, res) => {
  const rows = db
    .prepare(
      `SELECT r.id, r.reporter_user_id, r.target_user_id, r.message_id, r.reason, r.details, r.status, r.created_at,
              ru.username AS reporter_username, tu.username AS target_username
       FROM reports r
       LEFT JOIN users ru ON ru.id = r.reporter_user_id
       LEFT JOIN users tu ON tu.id = r.target_user_id
       ORDER BY r.status ASC, r.created_at DESC`,
    )
    .all();
  res.json({
    reports: rows.map((row) => ({
      id: row.id,
      reporterUserId: row.reporter_user_id,
      reporterUsername: row.reporter_username,
      targetUserId: row.target_user_id,
      targetUsername: row.target_username,
      messageId: row.message_id,
      reason: row.reason,
      details: row.details,
      status: row.status,
      createdAt: row.created_at,
    })),
  });
});

adminRouter.patch('/reports/:id', adminRequired, (req, res) => {
  const schema = z.object({ status: z.enum(['open', 'resolved', 'rejected']) });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  db.prepare('UPDATE reports SET status = ?, reviewed_at = ? WHERE id = ?').run(
    parsed.data.status,
    nowIso(),
    Number(req.params.id),
  );
  res.json({ ok: true });
});

adminRouter.post('/ban-user', adminRequired, (req, res) => {
  const schema = z.object({
    userId: z.number().int().positive(),
    reason: z.string().max(240).optional(),
    expiresAt: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  db.prepare(
    `INSERT INTO bans (user_id, reason, created_at, expires_at)
     VALUES (?, ?, ?, ?)`,
  ).run(
    parsed.data.userId,
    parsed.data.reason || 'Banned by admin',
    nowIso(),
    parsed.data.expiresAt || null,
  );
  db.prepare("UPDATE users SET status = 'banned', updated_at = ? WHERE id = ?").run(
    nowIso(),
    parsed.data.userId,
  );
  db.prepare('UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL').run(
    nowIso(),
    parsed.data.userId,
  );
  res.json({ ok: true });
});

adminRouter.post('/ban-ip-fingerprint', adminRequired, (req, res) => {
  const schema = z.object({
    ip: z.string().optional(),
    fingerprint: z.string().optional(),
    reason: z.string().max(240).optional(),
    expiresAt: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success || (!parsed.data.ip && !parsed.data.fingerprint)) {
    res.status(400).json({ error: 'IP or fingerprint is required' });
    return;
  }
  db.prepare(
    `INSERT INTO bans (ip, fingerprint, reason, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(
    parsed.data.ip || null,
    parsed.data.fingerprint || null,
    parsed.data.reason || 'Banned by admin',
    nowIso(),
    parsed.data.expiresAt || null,
  );
  res.json({ ok: true });
});

adminRouter.get('/stickerpacks', adminRequired, (_req, res) => {
  const packs = db
    .prepare(
      `SELECT p.id, p.owner_user_id, p.title, p.created_at,
              (SELECT COUNT(*) FROM stickers s WHERE s.pack_id = p.id) AS stickers_count
       FROM sticker_packs p
       ORDER BY p.id DESC`,
    )
    .all();
  res.json({
    packs: packs.map((row) => ({
      id: row.id,
      ownerUserId: row.owner_user_id,
      title: row.title,
      stickersCount: row.stickers_count,
      createdAt: row.created_at,
    })),
  });
});

adminRouter.delete('/stickerpacks/:id', adminRequired, (req, res) => {
  db.prepare('DELETE FROM sticker_packs WHERE id = ?').run(Number(req.params.id));
  res.json({ ok: true });
});

adminRouter.post('/server/restart', adminRequired, async (_req, res) => {
  if (!config.serverControlEnabled) {
    res.status(403).json({ error: 'Server control is disabled' });
    return;
  }
  try {
    await exec(config.restartCommand);
    res.json({ ok: true });
  } catch {
    res.status(500).json({ error: 'Failed to restart service' });
  }
});

adminRouter.post('/server/shutdown', adminRequired, async (_req, res) => {
  if (!config.serverControlEnabled) {
    res.status(403).json({ error: 'Server control is disabled' });
    return;
  }
  try {
    await exec(config.shutdownCommand);
    res.json({ ok: true });
  } catch {
    res.status(500).json({ error: 'Failed to shutdown server' });
  }
});
