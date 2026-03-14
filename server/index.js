import { WebSocketServer } from 'ws';
import { randomUUID } from 'node:crypto';

const port = Number(process.env.PORT || 8080);
const rooms = new Map();
const staleMemberMs = 45_000;

function getRoom(roomCode) {
  if (!rooms.has(roomCode)) {
    rooms.set(roomCode, { clients: new Map() });
  }
  return rooms.get(roomCode);
}

function sanitizeRoomCode(value) {
  return String(value || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9-]/g, '')
    .slice(0, 24);
}

function memberSnapshot(member) {
  return {
    id: member.id,
    name: member.name,
    isSharing: member.isSharing,
    lat: member.lat,
    lng: member.lng,
    accuracy: member.accuracy,
    updatedAt: member.updatedAt,
    isOnline: Date.now() - member.lastSeenAt < staleMemberMs,
  };
}

function broadcastRoomState(roomCode) {
  const room = rooms.get(roomCode);
  if (!room) return;

  const members = [...room.clients.values()].map(memberSnapshot);
  const payload = JSON.stringify({ type: 'room_state', roomCode, members });

  for (const member of room.clients.values()) {
    if (member.socket.readyState === member.socket.OPEN) {
      member.socket.send(payload);
    }
  }

  if (room.clients.size === 0) {
    rooms.delete(roomCode);
  }
}

function leaveRoom(member) {
  if (!member.roomCode) return;
  const room = rooms.get(member.roomCode);
  if (!room) return;
  room.clients.delete(member.id);
  broadcastRoomState(member.roomCode);
}

function touchMember(member) {
  member.lastSeenAt = Date.now();
}

function handleJoin(member, data) {
  const roomCode = sanitizeRoomCode(data.roomCode);
  const name = String(data.name || '').trim().slice(0, 40);

  if (!roomCode || !name) {
    member.socket.send(JSON.stringify({ type: 'error', message: 'roomCode and name are required' }));
    return;
  }

  leaveRoom(member);

  member.roomCode = roomCode;
  member.name = name;
  member.isSharing = Boolean(data.isSharing ?? true);
  touchMember(member);

  const room = getRoom(roomCode);
  room.clients.set(member.id, member);

  member.socket.send(JSON.stringify({
    type: 'joined',
    memberId: member.id,
    roomCode,
  }));

  broadcastRoomState(roomCode);
}

function handleLocation(member, data) {
  if (!member.roomCode) {
    member.socket.send(JSON.stringify({ type: 'error', message: 'join a room first' }));
    return;
  }

  member.lat = Number(data.lat);
  member.lng = Number(data.lng);
  member.accuracy = Number(data.accuracy || 0);
  member.updatedAt = new Date().toISOString();
  member.isSharing = Boolean(data.isSharing ?? true);
  touchMember(member);

  broadcastRoomState(member.roomCode);
}

function handleSharing(member, data) {
  if (!member.roomCode) {
    member.socket.send(JSON.stringify({ type: 'error', message: 'join a room first' }));
    return;
  }

  member.isSharing = Boolean(data.isSharing);
  member.updatedAt = new Date().toISOString();
  touchMember(member);
  broadcastRoomState(member.roomCode);
}

export function createServer({ port: requestedPort } = {}) {
  const wss = new WebSocketServer({ port: requestedPort ?? port });

  wss.on('connection', (socket) => {
    const member = {
      id: randomUUID(),
      socket,
      roomCode: null,
      name: 'Unknown',
      isSharing: false,
      lat: null,
      lng: null,
      accuracy: null,
      updatedAt: null,
      lastSeenAt: Date.now(),
    };

    socket.send(JSON.stringify({ type: 'welcome', message: 'Connected to family locator relay' }));

    socket.on('message', (raw) => {
      try {
        touchMember(member);
        const data = JSON.parse(String(raw));
        switch (data.type) {
          case 'join':
            handleJoin(member, data);
            break;
          case 'location':
            handleLocation(member, data);
            break;
          case 'sharing':
            handleSharing(member, data);
            break;
          case 'ping':
            socket.send(JSON.stringify({ type: 'pong', ts: Date.now() }));
            break;
          default:
            socket.send(JSON.stringify({ type: 'error', message: `unknown message type: ${data.type}` }));
        }
      } catch {
        socket.send(JSON.stringify({ type: 'error', message: 'invalid json payload' }));
      }
    });

    socket.on('close', () => {
      leaveRoom(member);
    });
  });

  return wss;
}

const isDirectRun = process.argv[1] && new URL(`file://${process.argv[1]}`).href === import.meta.url;

if (isDirectRun) {
  createServer();
  console.log(`Family locator relay listening on ws://0.0.0.0:${port}`);
}
