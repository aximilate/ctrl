import path from 'node:path';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const serverRoot = path.resolve(__dirname, '..');

dotenv.config({ path: path.join(serverRoot, '.env') });

const parseList = (value, fallback) =>
  (value || fallback)
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);

export const config = {
  port: Number(process.env.PORT || 8080),
  nodeEnv: process.env.NODE_ENV || 'development',
  apiBaseUrl: process.env.API_BASE_URL || 'http://localhost:8080',
  corsOrigin: parseList(process.env.CORS_ORIGIN, 'http://localhost:3000'),
  jwtAccessSecret: process.env.JWT_ACCESS_SECRET || 'ctrlchat_dev_access_secret',
  jwtAccessTtl: process.env.JWT_ACCESS_TTL || '15m',
  refreshTtlDays: Number(process.env.REFRESH_TTL_DAYS || 30),
  adminToken: process.env.ADMIN_TOKEN || 'ctrlchat_dev_admin',
  dbPath: process.env.DB_PATH || './data/ctrlchat.db',
  smtpHost: process.env.SMTP_HOST,
  smtpPort: Number(process.env.SMTP_PORT || 465),
  smtpSecure: String(process.env.SMTP_SECURE || 'true').toLowerCase() === 'true',
  smtpUser: process.env.SMTP_USER,
  smtpPass: process.env.SMTP_PASS,
  smtpFrom: process.env.SMTP_FROM || 'CtrlChat <no-reply@ctrlapp.ru>',
  serverControlEnabled:
    String(process.env.SERVER_CONTROL_ENABLED || 'false').toLowerCase() === 'true',
  restartCommand: process.env.SERVER_CONTROL_RESTART_COMMAND || 'systemctl restart ctrlchat-api',
  shutdownCommand: process.env.SERVER_CONTROL_SHUTDOWN_COMMAND || 'shutdown now',
};

export const allowedEmailDomains = new Set([
  'gmail.com',
  'googlemail.com',
  'outlook.com',
  'hotmail.com',
  'live.com',
  'msn.com',
  'yahoo.com',
  'yandex.ru',
  'ya.ru',
  'mail.ru',
  'inbox.ru',
  'list.ru',
  'bk.ru',
  'rambler.ru',
  'ro.ru',
  'icloud.com',
  'me.com',
  'proton.me',
  'protonmail.com',
  'aol.com',
  'gmx.com',
  'zoho.com',
]);
