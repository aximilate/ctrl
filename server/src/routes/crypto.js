import { Router } from 'express';
import { z } from 'zod';

import { db } from '../db.js';
import { authRequired } from '../services/auth.js';
import { nowIso } from '../utils/time.js';

export const cryptoRouter = Router();

cryptoRouter.post('/keys', authRequired, (req, res) => {
  const schema = z.object({
    identityPublicKey: z.string().min(16),
    signedPrekeyPublic: z.string().min(16),
    signedPrekeySignature: z.string().min(16),
    oneTimePrekeys: z.array(z.string().min(16)).max(200),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const timestamp = nowIso();
  db.prepare(
    `INSERT INTO user_keys
    (user_id, identity_public, signed_prekey_public, signed_prekey_signature, one_time_prekeys, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET
      identity_public = excluded.identity_public,
      signed_prekey_public = excluded.signed_prekey_public,
      signed_prekey_signature = excluded.signed_prekey_signature,
      one_time_prekeys = excluded.one_time_prekeys,
      updated_at = excluded.updated_at`,
  ).run(
    req.auth.userId,
    parsed.data.identityPublicKey,
    parsed.data.signedPrekeyPublic,
    parsed.data.signedPrekeySignature,
    JSON.stringify(parsed.data.oneTimePrekeys),
    timestamp,
    timestamp,
  );

  res.json({ ok: true });
});

cryptoRouter.get('/prekey/:username', authRequired, (req, res) => {
  const username = req.params.username.toLowerCase();
  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (!user) {
    res.status(404).json({ error: 'User not found' });
    return;
  }
  const keys = db
    .prepare(
      `SELECT identity_public, signed_prekey_public, signed_prekey_signature, one_time_prekeys
       FROM user_keys WHERE user_id = ?`,
    )
    .get(user.id);
  if (!keys) {
    res.status(404).json({ error: 'Keys are not uploaded yet' });
    return;
  }

  let oneTimePrekeys = [];
  try {
    oneTimePrekeys = JSON.parse(keys.one_time_prekeys || '[]');
  } catch {
    oneTimePrekeys = [];
  }
  const oneTimePrekey = oneTimePrekeys.shift() || null;
  db.prepare('UPDATE user_keys SET one_time_prekeys = ?, updated_at = ? WHERE user_id = ?').run(
    JSON.stringify(oneTimePrekeys),
    nowIso(),
    user.id,
  );
  res.json({
    userId: user.id,
    identityPublicKey: keys.identity_public,
    signedPrekeyPublic: keys.signed_prekey_public,
    signedPrekeySignature: keys.signed_prekey_signature,
    oneTimePrekey,
  });
});
