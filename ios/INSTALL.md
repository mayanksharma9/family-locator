# Install on iPhone

## What you need

- a Mac
- Xcode installed
- your iPhone connected by cable or trusted over network
- this repo cloned locally
- Flutter installed on the Mac

## 1) Start the relay

On the machine hosting the relay:

```bash
cd server
./run.sh
```

If your iPhone is on the same Wi‑Fi, note the machine's LAN IP, for example:

```text
192.168.1.25
```

You will use a relay URL like:

```text
ws://192.168.1.25:8080
```

## 2) Prepare the Flutter project

```bash
flutter pub get
cd ios
pod install
cd ..
```

If CocoaPods says it is already installed, that is fine.

## 3) Open the iOS workspace

Open this file in Xcode:

```text
ios/Runner.xcworkspace
```

Do **not** open `Runner.xcodeproj` directly.

## 4) Configure signing in Xcode

In Xcode:

1. Select the `Runner` project
2. Select the `Runner` target
3. Open **Signing & Capabilities**
4. Change the **Bundle Identifier** to something unique, for example:
   - `com.mayanksharma9.familylocator`
5. Choose your Apple ID / Team
6. Let Xcode create the provisioning profile

If you use a free Apple account, direct install on your own device is still possible, but provisioning is more limited than with a paid Apple Developer account.

## 5) Enable Developer Mode on the iPhone

On iPhone:
- go to **Settings > Privacy & Security > Developer Mode**
- enable it and restart if prompted

After first install, you may also need to trust your developer profile in:
- **Settings > General > VPN & Device Management**

## 6) Run from Xcode

1. Select your connected iPhone as the run target
2. Press **Run** in Xcode
3. Accept any signing or trust prompts

## 7) First launch permissions

When the app opens:
- allow **Location While Using** first
- if you want better background behavior, later switch to **Always** in iPhone Settings
- enter the relay URL and family code
- tap **Connect & share**

## 8) If the app cannot connect to the relay

Check these first:
- iPhone and relay host are on the same network
- firewall allows port `8080`
- relay is running
- the relay URL uses your LAN IP, not `localhost`
- example good URL: `ws://192.168.1.25:8080`

## Notes about iPhone behavior

- iOS may still reduce background activity over time
- this app is background-friendlier than before, but it is not equivalent to Apple's own Find My privileges
- for internet exposure, you should add TLS and stronger authentication before using this outside your home network
