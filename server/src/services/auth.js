import jwt from 'jsonwebtoken';

import { config } from '../config.js';
import { db, selectUserPublic } from '../db.js';
import { addDays, nowIso } from '../utils/time.js';
import {
  generateRefreshToken,
  generateSessionId,
  getClientFingerprint,
  hashToken,
  parseBearerToken,
} from '../utils/security.js';

export function createTokens(user, sessionId) {
  const accessToken = jwt.sign(
    { sub: user.id, sid: sessionId, username: user.username || null },
    config.jwtAccessSecret,
    { expiresIn: config.jwtAccessTtl },
  );
  const refreshToken = generateRefreshToken();
  return { accessToken, refreshToken };
}

export function createSessionForUser(user, req) {
  const sessionId = generateSessionId();
  const { accessToken, refreshToken } = createTokens(user, sessionId);

  db.prepare(
    `INSERT INTO sessions
    (id, user_id, refresh_hash, user_agent, ip, fingerprint, created_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    sessionId,
    user.id,
    hashToken(refreshToken),
    req.headers['user-agent']?.toString().slice(0, 255) ?? null,
    req.ip,
    getClientFingerprint(req),
    nowIso(),
    addDays(config.refreshTtlDays),
  );

  return { sessionId, accessToken, refreshToken };
}

export function authRequired(req, res, next) {
  const token = parseBearerToken(req);
  if (!token) {
    res.status(401).json({ error: 'Missing bearer token' });
    return;
  }

  try {
    const payload = jwt.verify(token, config.jwtAccessSecret);
    const user = selectUserPublic(Number(payload.sub));
    if (!user || user.status !== 'active') {
      res.status(401).json({ error: 'Invalid session user' });
      return;
    }
    req.auth = {
      userId: user.id,
      sessionId: String(payload.sid),
      user,
    };
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

export function adminRequired(req, res, next) {
  const adminToken = req.headers['x-admin-token'];
  const bearer = parseBearerToken(req);
  if (adminToken === config.adminToken || bearer === config.adminToken) {
    next();
    return;
  }
  res.status(401).json({ error: 'Admin token is required' });
}
