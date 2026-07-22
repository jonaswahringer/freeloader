# Scaffold the Freeloader Xcode project

Type: task (AFK)
Status: resolved

## Question

Stand up the SwiftUI multiplatform project so every later ticket has a place to build: Xcode project named Freeloader targeting macOS + iPadOS, SwiftData container wired with initial models (Book, ReadingPosition, Thread, Note — stubs are fine), app builds and launches on macOS and an iPad simulator. Record bundle id, minimum OS versions, and any project-structure conventions in the answer.

## Answer

Scaffolded, built, and launch-verified on 2026-07-22.

- **Project:** `Freeloader.xcodeproj` at repo root — hand-written modern pbxproj (objectVersion 77) using a **folder-synchronized group**: everything under `Freeloader/` is picked up automatically, no pbxproj edits needed when adding files.
- **One multiplatform target** `Freeloader`: `SDKROOT = auto`, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `TARGETED_DEVICE_FAMILY = 2` (iPad-only on the iOS side), Mac Catalyst off.
- **Bundle id:** `com.wahringer.freeloader`. **Min OS:** macOS 15.0 / iOS 18.0. Version 0.1.0.
- **Signing/sandbox:** automatic style, macOS signs ad hoc (`CODE_SIGN_IDENTITY = "-"`), **no entitlements file → app is unsandboxed**, hardened runtime off — deliberate, so ticket 07 can spawn the `claude` CLI. Generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`).
- **SwiftData** wired in `FreeloaderApp.swift` with stub models in `Freeloader/Models/Models.swift`: `Book`, `Chapter`, `BookSection` (named to dodge `SwiftUI.Section`), `ReadingPosition`, `DiscussionThread` + `ThreadMessage` (dodges `Foundation.Thread`), `Note` — cascade-delete relationships from Book. `ContentView` is a minimal empty-library placeholder.
- **Verified:** `xcodebuild` succeeds for `platform=macOS` and iPad Pro 11-inch (M5) simulator; the macOS app launches and runs (ModelContainer initializes).
- **Environment quirks:** Xcode 26.6 needed a one-time `xcodebuild -runFirstLaunch` (stale IDESimulatorFoundation plugin). iOS *device* platform (26.5) is not installed — simulator + macOS only; match simulator destinations by UDID (`platform=iOS Simulator,id=…`), name matching failed.
