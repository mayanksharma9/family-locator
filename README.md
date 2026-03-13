# Family Locator

A transparent, consent-based Flutter starter for simple family location sharing.

## Architecture

This version uses:
- a Flutter mobile app
- a tiny Node.js WebSocket relay
- no database
- no location history persistence

The relay keeps room membership and latest locations **in memory only**. If the relay restarts, the room state disappears.

## Current flow

1. Run the relay server
2. Open the app on each family member's phone
3. Enter the same relay URL and family code
4. Each person explicitly taps **Connect & share**
5. Live locations are forwarded to everyone in that room

## Safety model

This app is intentionally visible and consent-based:
- users must knowingly install it
- users must manually join a family code
- the app shows whether sharing is on or off
- users can pause or disconnect at any time
- there is no hidden mode or stealth tracking

## Run the relay

```bash
cd server
npm install
npm start
```

By default the relay listens on:

```bash
ws://localhost:8080
```

## Run the Flutter app

```bash
flutter pub get
flutter run
```

### Android emulator note
Use this relay URL inside the app:

```text
ws://10.0.2.2:8080
```

### iPhone / real devices
Use your computer's LAN IP, for example:

```text
ws://192.168.1.25:8080
```

Both phones and the relay server need to be reachable on the same network unless you deploy the relay publicly.

## Tests

Flutter:

```bash
flutter analyze
flutter test
```

Relay:

```bash
cd server
npm test
```

## Permissions included

### Android
- fine location
- coarse location
- background location declaration placeholder
- foreground service location declaration placeholder

### iOS
- when-in-use location usage description
- always-and-when-in-use usage description
- background location mode

## Limitations

- background behavior depends on platform rules
- GPS accuracy varies by device and environment
- no database means no history and no offline sync
- OpenStreetMap public tiles are okay for testing, but you should review tile-hosting policy before production use
