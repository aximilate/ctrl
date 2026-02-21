import { createHash, randomBytes, randomUUID } from 'node:crypto';

import { allowedEmailDomains } from '../config.js';

export function hashToken(value) {
  return createHash('sha256').update(value).digest('hex');
}

export function parseBearerToken(req) {
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) {
    return null;
  }
  return auth.slice('Bearer '.length).trim();
}

export function generateCode() {
  return `${Math.floor(100000 + Math.random() * 900000)}`;
}

export function generateSessionId() {
  return randomUUID();
}

export function generateRefreshToken() {
  return randomBytes(48).toString('hex');
}

export function isAllowedDomain(email) {
  const domain = email.toLowerCase().split('@')[1] || '';
  return allowedEmailDomains.has(domain);
}

export function getClientFingerprint(req) {
  const value = req.headers['x-device-fingerprint'];
  return typeof value === 'string' ? value : null;
}
