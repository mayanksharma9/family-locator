# Family Locator

A transparent, consent-based Flutter starter for family location sharing.

## What this project is

This app is intentionally built as a **visible** family location app:
- users must explicitly enable location sharing
- the UI always shows whether sharing is on or off
- users can stop sharing at any time
- there is no hidden mode and no stealth install behavior

## Current MVP

- Flutter app for iOS and Android
- OpenStreetMap map view via `flutter_map`
- current-device location permission flow via `geolocator`
- visible sharing status controls
- sample family member markers to demonstrate the UX

## What still needs real backend setup

To make this work like a real family-sharing product, you should connect it to a backend such as:
- Supabase Realtime
- Firebase Firestore + presence
- your own API + WebSocket updates

### Suggested backend shape

Table/collection ideas:
- `families`
- `family_members`
- `location_updates`
- `sharing_status`

Each device should:
1. authenticate as a real user
2. join a family group by invite
3. publish its latest location only when sharing is enabled
4. subscribe to other opted-in family members' latest locations

## Run locally

```bash
flutter pub get
flutter run
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

## Important

Do not use this app for covert monitoring. Everyone being tracked should know, consent, and be able to turn sharing off.
