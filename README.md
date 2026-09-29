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

Generates the project, runs the `OysterKit` tests, then builds the `Oyster` scheme (app + widget) and runs the app's `OysterTests` on the shared simulator. Override the simulator with `SIMULATOR_ID=<udid> scripts/test.sh`.

### Contract fixtures

`OysterKit/Sources/OysterKit/Contract/` mirrors the backend's `src/contract` (§2). The backend's canonical `fixtures/contract/` are copied verbatim into `OysterKit/Tests/OysterKitTests/Fixtures/contract/` (backend commit recorded in `SOURCE`). Re-sync after a backend contract change:

```sh
BACKEND_REPO=../backend scripts/sync-fixtures.sh   # BACKEND_REF defaults to origin/feat/oyster-plan-integration
```

## Layout

- `Oyster/` — app target (`com.aaronw122.oyster`): Chat and Pearls tabs, connect sheet; handles `oyster://oauth/complete` sign-in callbacks
- `OysterTests/` — app unit tests (chat view model against a scripted event stream)
- `OysterWidget/` — widget extension (`com.aaronw122.oyster.widget`)
- `OysterKit/` — shared library + tests; `AppGroup` / `SharedStore` for App Group storage; `Contract/` wire types
- App Group: `group.com.aaronw122.oyster` (both targets)
