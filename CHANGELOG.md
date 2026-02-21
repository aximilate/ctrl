# Changelog

## 0.1.0 - 2026-02-21

- Создан монорепозиторий `ctrlchat` (Flutter Web + Node.js API).
- Реализованы auth flows:
  - login с обязательным 2FA;
  - многошаговая registration (email/code/password/profile).
- Реализован desktop UI мессенджера:
  - левый capsule-nav;
  - списки чатов/контактов/звонков/настроек;
  - окно чата, контекстные меню, reply/edit/delete/report/reactions;
  - emoji/stickers popup, базовые voice/video-note режимы.
- Реализован backend:
  - Argon2id, JWT sessions;
  - users/privacy/sessions;
  - chats/messages/reactions/search/calls;
  - reports/stickers/admin.
- Добавлена web admin panel (`/admin`).
- Добавлена крипто-подсистема v1:
  - X25519 + HKDF-SHA-256 + XChaCha20-Poly1305.
- Обновлена документация по запуску и деплою на VPS.
