import { Router } from 'express';
import { z } from 'zod';

import { db } from '../db.js';
import { authRequired } from '../services/auth.js';
import { nowIso } from '../utils/time.js';

export const reportsRouter = Router();

reportsRouter.post('/', authRequired, (req, res) => {
  const schema = z.object({
    targetUserId: z.number().int().positive().optional(),
    messageId: z.string().optional(),
    reason: z.string().min(3).max(120),
    details: z.string().max(1000).optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const info = db
    .prepare(
      `INSERT INTO reports (reporter_user_id, target_user_id, message_id, reason, details, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .run(
      req.auth.userId,
      parsed.data.targetUserId ?? null,
      parsed.data.messageId ?? null,
      parsed.data.reason,
      parsed.data.details ?? null,
      nowIso(),
    );
  res.json({ ok: true, reportId: Number(info.lastInsertRowid) });
});
