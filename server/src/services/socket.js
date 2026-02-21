import jwt from 'jsonwebtoken';
import { Server } from 'socket.io';

import { config } from '../config.js';
import { selectUserPublic } from '../db.js';
import { isUserInChat } from './chats.js';

let io = null;

export function setupSocket(httpServer) {
  io = new Server(httpServer, {
    cors: {
      origin: config.corsOrigin,
      credentials: true,
    },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token || typeof token !== 'string') {
      next(new Error('Unauthorized'));
      return;
    }
    try {
      const payload = jwt.verify(token, config.jwtAccessSecret);
      const userId = Number(payload.sub);
      const user = selectUserPublic(userId);
      if (!user || user.status !== 'active') {
        next(new Error('Unauthorized'));
        return;
      }
      socket.data.userId = userId;
      next();
    } catch {
      next(new Error('Unauthorized'));
    }
  });

  io.on('connection', (socket) => {
    const userId = socket.data.userId;
    socket.join(`user:${userId}`);

    socket.on('chat:join', (chatId) => {
      if (typeof chatId !== 'string') {
        return;
      }
      if (!isUserInChat(chatId, userId)) {
        return;
      }
      socket.join(`chat:${chatId}`);
    });

    socket.on('chat:leave', (chatId) => {
      if (typeof chatId !== 'string') {
        return;
      }
      socket.leave(`chat:${chatId}`);
    });
  });

  return io;
}

export function getIo() {
  return io;
}
