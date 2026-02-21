import { Router } from 'express';

import { nowIso } from '../utils/time.js';

export const healthRouter = Router();

healthRouter.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'ctrlchat-server',
    time: nowIso(),
  });
});
