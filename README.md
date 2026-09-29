# Oyster iOS

SwiftUI app + WidgetKit extension. Shared code lives in the local Swift package `OysterKit/`.

## Prerequisites

- Xcode 27+ (iOS 17.0 deployment target, Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

The Xcode project is generated from `project.yml` and is not committed:

```sh
xcodegen generate
open Oyster.xcodeproj
```

## Test

```sh
scripts/test.sh
```

Generates the project, runs the `OysterKit` tests, and builds the `Oyster` scheme (app + widget) on the shared simulator. Override the simulator with `SIMULATOR_ID=<udid> scripts/test.sh`.

## Layout

- `Oyster/` — app target (`com.aaronw122.oyster`)
- `OysterWidget/` — widget extension (`com.aaronw122.oyster.widget`)
- `OysterKit/` — shared library + tests; `AppGroup` / `SharedStore` for App Group storage
- App Group: `group.com.aaronw122.oyster` (both targets)
