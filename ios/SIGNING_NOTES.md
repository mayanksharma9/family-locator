# iOS signing notes

Default placeholder bundle identifier in this repo:

```text
com.example.familyLocator
```

Before installing on a real iPhone, change it in Xcode to something unique, for example:

```text
com.mayanksharma9.familylocator
```

## Where to change it

In Xcode:
- open `ios/Runner.xcworkspace`
- select the `Runner` target
- open **Signing & Capabilities**
- edit **Bundle Identifier**
- choose your Team

## Notes

- the repo keeps a generic placeholder so it can stay reusable
- the actual signing identity should be chosen locally in Xcode
- if you later use TestFlight, keep the bundle identifier stable
