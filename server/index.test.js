import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { createServer } from './index.js';

function waitForMessage(socket, matcher) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timed out waiting for message')), 4000);
    socket.on('message', function handler(raw) {
      const parsed = JSON.parse(String(raw));
      if (!matcher || matcher(parsed)) {
        clearTimeout(timer);
        socket.off('message', handler);
        resolve(parsed);
      }
    });
  });
}

test('relay broadcasts room state without persistence', async () => {
  const server = createServer({ port: 0 });
  const httpServer = await new Promise((resolve) => {
    server.on('listening', () => resolve(server));
  });

  const { port } = httpServer.address();
  const a = new WebSocket(`ws://127.0.0.1:${port}`);
  const b = new WebSocket(`ws://127.0.0.1:${port}`);

  await Promise.all([
    new Promise((resolve) => a.once('open', resolve)),
    new Promise((resolve) => b.once('open', resolve)),
  ]);

  let next = waitForMessage(a, (m) => m.type === 'joined');
  a.send(JSON.stringify({ type: 'join', roomCode: 'HOME123', name: 'Leo' }));
  await next;

  next = waitForMessage(a, (m) => m.type === 'room_state' && m.members.length === 1);
  a.send(JSON.stringify({ type: 'location', lat: 37.1, lng: -122.1, accuracy: 8, isSharing: true }));
  await next;

  next = waitForMessage(b, (m) => m.type === 'joined');
  b.send(JSON.stringify({ type: 'join', roomCode: 'HOME123', name: 'Ava' }));
  await next;

  next = waitForMessage(a, (m) => m.type === 'room_state' && m.members.length === 2);
  b.send(JSON.stringify({ type: 'location', lat: 37.2, lng: -122.2, accuracy: 12, isSharing: true }));
  const state = await next;

  assert.equal(state.roomCode, 'HOME123');
  assert.equal(state.members.some((member) => member.name === 'Leo'), true);
  assert.equal(state.members.some((member) => member.name === 'Ava'), true);
  assert.equal(state.members.every((member) => typeof member.isOnline === 'boolean'), true);

  a.close();
  b.close();
  await new Promise((resolve) => httpServer.close(resolve));
});
