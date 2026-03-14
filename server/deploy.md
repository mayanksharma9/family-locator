# Relay deploy notes

## Quick local run

```bash
cd server
./run.sh
```

## Small VPS / home server setup

1. Install Node.js 20+
2. Copy the `server/` directory to the machine
3. Run:

```bash
npm install
PORT=8080 node index.js
```

## systemd example

```ini
[Unit]
Description=Family Locator Relay
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/family-locator/server
ExecStart=/usr/bin/env PORT=8080 node index.js
Restart=always
RestartSec=3
User=familylocator
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

## Reverse proxy note

If you expose this publicly, put it behind a reverse proxy that supports WebSockets.

## Security note

This relay is intentionally simple and has no auth beyond a shared room code. For any real internet exposure, add authentication and TLS.
