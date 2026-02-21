import crypto from 'node:crypto';

import argon2 from 'argon2';
import { Router } from 'express';
import { z } from 'zod';

import { config } from '../config.js';
import { allocateUserId, bannedReason, db, selectUserPublic, serializeUser } from '../db.js';
import { createSessionForUser, createTokens, authRequired } from '../services/auth.js';
import { sendCodeEmail } from '../services/mailer.js';
import { addDays, addMinutes, nowIso } from '../utils/time.js';
import { generateCode, getClientFingerprint, hashToken, isAllowedDomain } from '../utils/security.js';

export const authRouter = Router();

authRouter.post('/register/request-code', async (req, res) => {
  const schema = z.object({ email: z.string().email() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid email' });
    return;
  }

  const email = parsed.data.email.trim().toLowerCase();
  if (!isAllowedDomain(email)) {
    res.status(400).json({ error: 'Email domain is not allowed' });
    return;
  }

  const existing = db.prepare('SELECT 1 FROM users WHERE email = ?').get(email);
  if (existing) {
    res.status(409).json({ error: 'Email is already registered' });
    return;
  }

  const ban = bannedReason({
    ip: req.ip,
    fingerprint: getClientFingerprint(req),
  });
  if (ban) {
    res.status(403).json({ error: ban });
    return;
  }

  const code = generateCode();
  db.prepare(
    `INSERT INTO verification_codes (email, purpose, code, expires_at, created_at)
     VALUES (?, 'register', ?, ?, ?)`,
  ).run(email, code, addMinutes(10), nowIso());

  try {
    await sendCodeEmail(email, code, 'register');
    res.json({ ok: true, ...(config.nodeEnv !== 'production' ? { devCode: code } : {}) });
  } catch {
    res.status(500).json({ error: 'Failed to send code' });
  }
});

authRouter.post('/register/verify-code', (req, res) => {
  const schema = z.object({
    email: z.string().email(),
    code: z.string().regex(/^\d{6}$/),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const email = parsed.data.email.trim().toLowerCase();
  const code = parsed.data.code;
  const now = nowIso();
  const record = db
    .prepare(
      `SELECT * FROM verification_codes
       WHERE email = ? AND purpose = 'register' AND consumed_at IS NULL AND expires_at > ?
       ORDER BY created_at DESC LIMIT 1`,
    )
    .get(email, now);

  if (!record || record.code !== code) {
    res.status(400).json({ error: 'Invalid or expired code' });
    return;
  }

  db.prepare('UPDATE verification_codes SET consumed_at = ? WHERE id = ?').run(nowIso(), record.id);
  const registrationToken = crypto.randomUUID();
  db.prepare(
    `INSERT INTO registration_flows (token, email, code_verified_at, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(registrationToken, email, nowIso(), nowIso(), addMinutes(30));
  res.json({ registrationToken });
});

authRouter.post('/register/set-password', async (req, res) => {
  const schema = z.object({
    registrationToken: z.string().min(10),
    password: z.string().min(8).max(128),
    passwordConfirm: z.string().min(8).max(128),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }
  const { registrationToken, password, passwordConfirm } = parsed.data;
  if (password !== passwordConfirm) {
    res.status(400).json({ error: 'Passwords do not match' });
    return;
  }

  const flow = db
    .prepare('SELECT * FROM registration_flows WHERE token = ? AND expires_at > ?')
    .get(registrationToken, nowIso());
  if (!flow) {
    res.status(400).json({ error: 'Registration token expired or invalid' });
    return;
  }

  const passwordHash = await argon2.hash(password, { type: argon2.argon2id });
  db.prepare('UPDATE registration_flows SET password_hash = ? WHERE token = ?').run(
    passwordHash,
    registrationToken,
  );
  res.json({ ok: true });
});

authRouter.post('/register/complete-profile', (req, res) => {
  const schema = z.object({
    registrationToken: z.string(),
    displayName: z.string().min(1).max(64),
    username: z.string().regex(/^[a-z0-9_]{4,24}$/),
    avatarUrl: z.string().url().optional().or(z.literal('')),
    bio: z.string().max(200).optional(),
    identityPublicKey: z.string().optional(),
    signedPrekeyPublic: z.string().optional(),
    signedPrekeySignature: z.string().optional(),
    oneTimePrekeys: z.array(z.string()).max(100).optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const flow = db
    .prepare('SELECT * FROM registration_flows WHERE token = ? AND expires_at > ?')
    .get(parsed.data.registrationToken, nowIso());
  if (!flow || !flow.password_hash) {
    res.status(400).json({ error: 'Registration flow is not ready' });
    return;
  }

  const username = parsed.data.username.toLowerCase();
  const usernameExists = db.prepare('SELECT 1 FROM users WHERE username = ?').get(username);
  if (usernameExists) {
    res.status(409).json({ error: 'Username is already taken' });
    return;
  }
  const emailExists = db.prepare('SELECT 1 FROM users WHERE email = ?').get(flow.email);
  if (emailExists) {
    res.status(409).json({ error: 'Email is already registered' });
    return;
  }

  const id = allocateUserId();
  const timestamp = nowIso();
  db.prepare(
    `INSERT INTO users (id, email, username, display_name, avatar_url, bio, password_hash, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    id,
    flow.email,
    username,
    parsed.data.displayName,
    parsed.data.avatarUrl || null,
    parsed.data.bio || '',
    flow.password_hash,
    timestamp,
    timestamp,
  );
  db.prepare('INSERT INTO user_privacy (user_id) VALUES (?)').run(id);

  if (
    parsed.data.identityPublicKey &&
    parsed.data.signedPrekeyPublic &&
    parsed.data.signedPrekeySignature
  ) {
    db.prepare(
      `INSERT INTO user_keys
      (user_id, identity_public, signed_prekey_public, signed_prekey_signature, one_time_prekeys, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      parsed.data.identityPublicKey,
      parsed.data.signedPrekeyPublic,
      parsed.data.signedPrekeySignature,
      JSON.stringify(parsed.data.oneTimePrekeys || []),
      timestamp,
      timestamp,
    );
  }

  db.prepare('DELETE FROM registration_flows WHERE token = ?').run(parsed.data.registrationToken);

  const user = selectUserPublic(id);
  const session = createSessionForUser(user, req);
  res.json({
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: serializeUser(user),
  });
});

authRouter.post('/login/request', async (req, res) => {
  const schema = z.object({
    email: z.string().email(),
    password: z.string().min(8).max(128),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const email = parsed.data.email.trim().toLowerCase();
  const userRow = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
  if (!userRow) {
    res.status(401).json({ error: 'Invalid credentials' });
    return;
  }
  if (userRow.status !== 'active') {
    res.status(403).json({ error: 'Account is blocked' });
    return;
  }

  const ban = bannedReason({
    userId: userRow.id,
    ip: req.ip,
    fingerprint: getClientFingerprint(req),
  });
  if (ban) {
    res.status(403).json({ error: ban });
    return;
  }

  const ok = await argon2.verify(userRow.password_hash, parsed.data.password);
  if (!ok) {
    res.status(401).json({ error: 'Invalid credentials' });
    return;
  }

  const code = generateCode();
  const challengeId = crypto.randomUUID();
  db.prepare(
    `INSERT INTO login_challenges (id, user_id, code, expires_at, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(challengeId, userRow.id, code, addMinutes(10), nowIso());

  try {
    await sendCodeEmail(email, code, 'login');
    res.json({ challengeId, ...(config.nodeEnv !== 'production' ? { devCode: code } : {}) });
  } catch {
    res.status(500).json({ error: 'Failed to send code' });
  }
});

authRouter.post('/login/verify', (req, res) => {
  const schema = z.object({
    challengeId: z.string(),
    code: z.string().regex(/^\d{6}$/),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const challenge = db
    .prepare(
      `SELECT * FROM login_challenges
       WHERE id = ? AND consumed_at IS NULL AND expires_at > ?`,
    )
    .get(parsed.data.challengeId, nowIso());

  if (!challenge || challenge.code !== parsed.data.code) {
    res.status(400).json({ error: 'Invalid or expired code' });
    return;
  }

  db.prepare('UPDATE login_challenges SET consumed_at = ? WHERE id = ?').run(
    nowIso(),
    challenge.id,
  );

  const user = selectUserPublic(challenge.user_id);
  const session = createSessionForUser(user, req);
  res.json({
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: serializeUser(user),
  });
});

authRouter.post('/refresh', (req, res) => {
  const schema = z.object({ refreshToken: z.string().min(20) });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid payload' });
    return;
  }

  const now = nowIso();
  const session = db
    .prepare(
      `SELECT * FROM sessions
       WHERE refresh_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
    )
    .get(hashToken(parsed.data.refreshToken), now);

  if (!session) {
    res.status(401).json({ error: 'Invalid refresh token' });
    return;
  }

  const user = selectUserPublic(session.user_id);
  if (!user || user.status !== 'active') {
    res.status(401).json({ error: 'Invalid session user' });
    return;
  }

  const tokens = createTokens(user, session.id);
  db.prepare('UPDATE sessions SET refresh_hash = ?, expires_at = ? WHERE id = ?').run(
    hashToken(tokens.refreshToken),
    addDays(config.refreshTtlDays),
    session.id,
  );

  res.json({
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    user: serializeUser(user),
  });
});

authRouter.post('/logout', authRequired, (req, res) => {
  db.prepare('UPDATE sessions SET revoked_at = ? WHERE id = ?').run(nowIso(), req.auth.sessionId);
  res.json({ ok: true });
});

authRouter.get('/me', authRequired, (req, res) => {
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
