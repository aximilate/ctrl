# ctrlchat

Рабочий монорепозиторий веб-мессенджера `ctrlchat`:
- `Flutter Web` клиент (desktop-first UI).
- `Node.js + Express + SQLite` API.
- обязательный `2FA` для входа (пароль + код из email).
- admin panel (`/admin`) для банов/жалоб/стикерпаков/управления сервером.

## Структура

- `lib/` — Flutter Web клиент.
- `server/` — backend API.
- `server/src/public/admin.html` — админ-панель.

## Реализовано

- Лэндинг/авторизация:
  - typewriter-анимация слева;
  - login: email+password -> обязательный 2FA код;
  - registration: email -> код -> пароль -> профиль (имя/username/аватар).
- Веб-интерфейс мессенджера (desktop):
  - левая капсула навигации;
  - список чатов/контактов/звонков/настроек;
  - контекстные меню по чатам и сообщениям;
  - reply/edit/delete/report/reaction;
  - поле ввода с attach + emoji/stickers + voice/video-note режимами (UI).
- Backend:
  - Argon2id хеш паролей;
  - JWT access + refresh sessions;
  - регистрация/логин/refresh/logout;
  - пользователи/приватность/активные сессии;
  - direct chats, messages, reactions, поиск;
  - sticker packs + reports;
  - bans (user/ip/fingerprint);
  - admin endpoints.
- Крипто-подсистема (v1):
  - X25519 ключи аккаунта;
  - HKDF-SHA-256;
  - XChaCha20-Poly1305 шифрование payload;
  - ключевые endpoint'ы для prekey bundle.

## Быстрый локальный запуск

### 1) Backend

```bash
cd server
cp .env.example .env
npm install
npm run start
```

API: `http://localhost:8080/api`  
Admin panel: `http://localhost:8080/admin`

### 2) Flutter Web

```bash
flutter pub get
flutter run -d chrome --dart-define=CTRLCHAT_API_URL=http://localhost:8080/api
```

## SMTP (mail.ru)

Заполните `server/.env`:

```env
SMTP_HOST=smtp.mail.ru
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=no-reply@ctrlapp.ru
SMTP_PASS=...
SMTP_FROM="CtrlChat <no-reply@ctrlapp.ru>"
```

Без SMTP в `development` коды будут возвращаться как `devCode` в API ответах.

## Деплой на VPS (176.32.37.18)

Целевой сценарий:
- фронтенд (статический build Flutter) на `ctrlapp.ru`;
- API на `web.ctrlapp.ru` (`/api` + `/admin`).

Рекомендуемая схема:
1. Собрать frontend:
```bash
flutter build web --release --dart-define=CTRLCHAT_API_URL=https://web.ctrlapp.ru/api
```
2. Залить `build/web` в `/var/www/ctrlchat`.
3. Развернуть `server/` в `/opt/ctrlchat/server`, установить зависимости `npm ci --omit=dev`.
4. Запустить API как systemd service (`ctrlchat-api`), проксировать через Nginx.

Пример Nginx:
- `server_name ctrlapp.ru` -> `root /var/www/ctrlchat`.
- `server_name web.ctrlapp.ru` -> `proxy_pass http://127.0.0.1:8080`.

## API (основные маршруты)

- `POST /api/auth/register/request-code`
- `POST /api/auth/register/verify-code`
- `POST /api/auth/register/set-password`
- `POST /api/auth/register/complete-profile`
- `POST /api/auth/login/request`
- `POST /api/auth/login/verify`
- `POST /api/auth/refresh`
- `GET /api/auth/me`
- `GET /api/chats`
- `GET /api/chats/:chatId/messages`
- `POST /api/chats/:chatId/messages`
- `POST /api/messages/:messageId/reactions`
- `GET /api/search`
- `GET /api/admin/overview`
- `GET /api/admin/reports`
- `GET /api/admin/stickerpacks`

## Команды проверки

```bash
flutter analyze --no-fatal-infos
flutter build web --release
cd server && node --check src/index.js
```

## Важно

- В git игнорируются: `server/.env`, `server/data`, `server/node_modules`.
- Email-домены регистрации ограничены whitelist'ом (gmail/outlook/yandex/mail/rambler и др).
- Логика переиспользования `id` пользователя реализована (берется первая свободная дырка в последовательности id).
