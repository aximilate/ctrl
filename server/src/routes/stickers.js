import { Router } from 'express';
import { z } from 'zod';

import { db } from '../db.js';
import { authRequired } from '../services/auth.js';
import { nowIso } from '../utils/time.js';

export const stickersRouter = Router();

stickersRouter.get('/packs', authRequired, (_req, res) => {
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
      shareUrl: `https://ctrlchat.ru/stikerpack/${row.id}`,
      createdAt: row.created_at,
    })),
  });
});

stickersRouter.post('/packs', authRequired, (req, res) => {
  const schema = z.object({ title: z.string().min(1).max(64) });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const info = db
    .prepare('INSERT INTO sticker_packs (owner_user_id, title, created_at) VALUES (?, ?, ?)')
    .run(req.auth.userId, parsed.data.title, nowIso());
  res.json({
    id: Number(info.lastInsertRowid),
    shareUrl: `https://ctrlchat.ru/stikerpack/${info.lastInsertRowid}`,
  });
});

stickersRouter.post('/packs/:packId/items', authRequired, (req, res) => {
  const schema = z.object({
    imageUrl: z.string().url(),
    sortOrder: z.number().int().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const packId = Number(req.params.packId);
  const pack = db.prepare('SELECT owner_user_id FROM sticker_packs WHERE id = ?').get(packId);
  if (!pack) {
    res.status(404).json({ error: 'Sticker pack not found' });
    return;
  }
  if (pack.owner_user_id !== req.auth.userId) {
    res.status(403).json({ error: 'Only owner can edit sticker pack' });
    return;
  }
  const info = db
    .prepare(
      `INSERT INTO stickers (pack_id, image_url, sort_order, created_at)
       VALUES (?, ?, ?, ?)`,
    )
    .run(packId, parsed.data.imageUrl, parsed.data.sortOrder ?? 0, nowIso());
  res.json({ id: Number(info.lastInsertRowid) });
});
