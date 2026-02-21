import nodemailer from 'nodemailer';

import { config } from '../config.js';

const transporter =
  config.smtpHost && config.smtpUser && config.smtpPass
    ? nodemailer.createTransport({
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpSecure,
        auth: {
          user: config.smtpUser,
          pass: config.smtpPass,
        },
      })
    : null;

export async function sendCodeEmail(email, code, purpose) {
  if (!transporter) {
    if (config.nodeEnv !== 'production') {
      console.log(`[MAIL_DISABLED] ${purpose} code for ${email}: ${code}`);
      return;
    }
    throw new Error('SMTP is not configured');
  }

  const subject =
    purpose === 'login' ? 'CtrlChat: код входа (2FA)' : 'CtrlChat: код подтверждения регистрации';
  const text = `Ваш код: ${code}. Он действует 10 минут.`;

  await transporter.sendMail({
    from: config.smtpFrom,
    to: email,
    subject,
    text,
  });
}
