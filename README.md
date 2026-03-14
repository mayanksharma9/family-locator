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
6. If the relay drops, the app automatically retries with backoff
7. Users can refresh location, recenter the map, pause sharing, or open settings

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
./run.sh
```

By default the relay listens on:

```bash
ws://localhost:8080
```

More deploy notes: `server/deploy.md`

## Run the Flutter app

```bash
flutter pub get
flutter run
```

## Install on iPhone

See: `ios/INSTALL.md`

Short version:
- open `ios/Runner.xcworkspace` in Xcode on a Mac
- set a unique bundle identifier
- choose your Apple signing team
- run the app on your connected iPhone
- use a LAN relay URL like `ws://192.168.1.25:8080`

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

## Background location notes

This build now uses platform-specific location settings aimed at better active/background behavior:
- Android foreground notification config for active sharing
- iOS background location update flags
- tighter GPS update intervals and distance filters

But the real constraint is still the OS. Background delivery can be delayed or reduced by:
- battery optimization
- app suspension
- permission level (`While Using` vs `Always`)
- poor GPS or network conditions

So this is more robust, but still not magic.

## Performance notes

This build is tuned for a simple low-latency MVP:
- location stream uses high-accuracy settings
- location updates send after small movement changes
- WebSocket ping keeps the relay session warm
- reconnect retries use capped backoff

Still, no honest mobile app can promise literally zero lag.

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
- room code alone is weak auth for internet exposure
- OpenStreetMap public tiles are okay for testing, but you should review tile-hosting policy before production use
