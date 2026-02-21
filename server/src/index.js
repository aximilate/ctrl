import path from 'node:path';
import { fileURLToPath } from 'node:url';

import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';

import { config } from './config.js';
import './db.js';
import { adminRouter } from './routes/admin.js';
import { authRouter } from './routes/auth.js';
import { chatRouter } from './routes/chat.js';
import { cryptoRouter } from './routes/crypto.js';
import { healthRouter } from './routes/health.js';
import { reportsRouter } from './routes/reports.js';
import { stickersRouter } from './routes/stickers.js';
import { usersRouter } from './routes/users.js';
import { setupSocket } from './services/socket.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(
  cors({
    origin(origin, callback) {
      if (!origin || config.corsOrigin.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('CORS blocked'));
    },
    credentials: true,
  }),
);
app.use(express.json({ limit: '2mb' }));
app.use(morgan('dev'));
app.use('/admin', express.static(path.join(__dirname, 'public')));

app.use('/api', healthRouter);
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);
app.use('/api', chatRouter);
app.use('/api/stickers', stickersRouter);
app.use('/api/reports', reportsRouter);
app.use('/api/crypto', cryptoRouter);
app.use('/api/admin', adminRouter);

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: 'Internal server error' });
});

const httpServer = app.listen(config.port, () => {
  console.log(`ctrlchat-server is running at http://localhost:${config.port}`);
});

setupSocket(httpServer);
