# GardenPlanner — Developer Guide

GardenPlanner is a native macOS app built with **SwiftUI** and the **Swift Package Manager** (no `.xcodeproj`/`.xcworkspace` — Xcode opens the `Package.swift` directly). It targets macOS 14+ and uses Swift 6 with strict concurrency checking.

For what the app does from a user's perspective, see [USER_GUIDE.md](USER_GUIDE.md).

---

## Project layout

```
Package.swift
build-and-install.sh          — release build + app bundle assembly + install to /Applications
Sources/GardenPlanner/
  GardenPlannerApp.swift        — @main entry point, WindowGroup + Settings scene
  AppData.swift                 — single @Observable model: state, persistence, web server lifecycle
  WebServer.swift               — embedded HTTP server + mobile web UI (HTML/CSS/JS as a Swift string)
  Info.plist                    — linked into the binary manually (see "Linker quirk" below)
  Models/
    Seed.swift                  — Seed, SowingWindow, SowDateSpec, SunRequirement
    PlantingRecord.swift        — PlantingRecord, PlantLocation, Outcome, GridPosition
    GardenBed.swift             — GardenBed, BedCell
  Views/
    ContentView.swift           — top-level NavigationSplitView + sidebar section switch
    SeedCatalogView.swift       — seed list/detail/edit
    SowingCalendarView.swift    — year calendar grid + Planting Log overlay dots
    PlantingLogView.swift       — per-seed sowing timeline + record detail inspector
    GardenBedPlannerView.swift  — bed grid, drag/drop planting, cursor-anchored zoom
    SettingsView.swift          — frost dates, mobile web access, data location
  Resources/
    Assets.xcassets/            — AppIcon asset catalog (used by Xcode builds)
    AppIcon.icns                — compiled icon used by the release app bundle
```

There is no test target yet.

---

## Building and installing

### Normal workflow (recommended)

Run the build script from the project root:

```bash
./build-and-install.sh
```

This does everything in one step:
1. `swift build -c release` (using the custom Xcode toolchain — see below)
2. Assembles `GardenPlanner.app` with the correct bundle structure, `Info.plist`, and `AppIcon.icns`
3. Ad-hoc code-signs the bundle
4. Copies it to `/Applications`, replacing any previous version

Launch from Spotlight, Finder → Applications, or the Dock.

### Xcode toolchain path

Xcode on this machine is at a non-standard path (system Xcode is broken on the current macOS). All CLI builds must point at it explicitly. The build script handles this automatically; if you need to run `swift build` manually:

```bash
DEVELOPER_DIR=/Volumes/ORICO/Applications/Xcode.app/Contents/Developer \
  /Volumes/ORICO/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift build
```

You can also open the package in Xcode and use ⌘R for development iteration — Xcode's build lives in `DerivedData` and is completely separate from `swift build`'s `.build/` output. For testing UI changes quickly, Xcode is faster; for producing an installable app, use `build-and-install.sh`.

### App bundle structure

The `build-and-install.sh` script produces:

```
GardenPlanner.app/
  Contents/
    MacOS/
      GardenPlanner         — release binary
    Resources/
      AppIcon.icns          — icon at all macOS sizes
    Info.plist              — proper bundle Info.plist (separate from the binary-embedded one)
```

The bundle `Info.plist` includes `CFBundleIconFile = AppIcon`, which is how macOS loads the Dock and Finder icon. This is separate from the `Info.plist` embedded in the binary via linker flags (see below) — they serve different purposes.

---

## Linker quirk: embedded Info.plist

`Sources/GardenPlanner/Info.plist` is linked into the binary via `unsafeFlags` in `Package.swift`, embedding it in the `__TEXT,__info_plist` Mach-O section. This is what allows `NSApp.setActivationPolicy(.regular)` (in `GardenPlannerApp.swift`) to make the process behave like a normal foreground app with a menu bar and Dock icon, rather than a headless command-line tool. This section is only read when the binary runs without a bundle (e.g. directly from `.build/debug/`).

When the app runs as a proper bundle (from `/Applications`), macOS reads the bundle's `Contents/Info.plist` instead. The build script writes this file explicitly, so both paths work correctly.

---

## Data model and persistence

`AppData` (`AppData.swift`) is the single source of truth — an `@Observable` class injected into the SwiftUI environment from `GardenPlannerApp`. All collections (`seeds`, `plantingRecords`, `gardenBeds`, `customLocations`, frost dates, web server settings) use `didSet { save() }` so any mutation anywhere in the app immediately persists to disk:

```
~/Documents/GardenPlanner/Data/garden.json
```

`save()`/`load()` go through a private `AppDataFile: Codable` struct. **All fields added after the initial version are `Optional` with `?? defaultValue` fallbacks in `load()`** — this is the established pattern for schema evolution; never make a new field non-optional without a migration path, since old `garden.json` files won't have it.

`PlantLocation` (in `PlantingRecord.swift`) is a hand-written `Codable` enum that supports two on-disk shapes:
- New format: `{"type": "bed"|"custom", "id": ..., "name": ...}`
- Legacy format: a bare string (from before `PlantLocation` existed)

`init(from:)` tries the new keyed format first and falls back to a plain string decode. Follow this same try/fallback pattern if you need to change any other model's wire format.

Mutating methods on `AppData` (`addSeed`, `plantSeed`, `clearCell`, `addPlantingRecord`, etc.) are the only places that should mutate the model collections. Notably, `addPlantingRecord` also decrements the seed's `quantityPackets` — if you add another place that logs a planting, route it through this method or stock tracking will silently drift.

### Navigation signal

`AppData` has a transient (non-persisted) property `pendingBedNavigation: UUID?`. Setting it to a bed's UUID causes `ContentView` to switch to the Garden Beds section and `GardenBedPlannerView` to select that bed, then clears itself. This is how "Log Planting → navigate to bed" works on the desktop. It is not saved to disk.

---

## The embedded web server (`WebServer.swift`)

This is the most unusual part of the codebase, so it's worth understanding before touching it.

**Why it exists:** the user wanted to log plantings from an Android phone while standing in the garden. Rather than building a second client or a sync backend, the app serves its own data as a small mobile web page over the local network (reached via Tailscale from outside the LAN).

**Why raw POSIX sockets, not `Network.framework`:** an earlier version used `NWListener`, which proved unreliable in practice (state machine sometimes never reached `.ready`). It was replaced with a `final class WebServer: @unchecked Sendable` built directly on `socket()`/`bind()`/`listen()`/`accept()`/`read()`/`write()` from Darwin. If you're tempted to "modernise" this back to `Network.framework`, be aware of why it was moved away from — test thoroughly under real network conditions before doing so.

**Threading model:** `acceptLoop()` and `handleClient(_:)` run on a background `DispatchQueue`. Because `AppData` must only be touched on the main thread, each request's data work is dispatched to `.main` and the socket thread blocks on a `DispatchSemaphore` until it's done. The result is handed back via a small `final class Box: @unchecked Sendable { var data = Data() }` wrapper. Keep new endpoints inside this same dispatch → main-thread-closure → semaphore pattern.

**Routing:** `dispatch(method:path:body:appData:)` is a simple manual switch over `(method, path)`. `GET /` serves the entire mobile UI as one big string (`Self.pageHTML`); everything else under `/api/...` is JSON in, JSON out, with small private `Decodable`/`Encodable` structs scoped to each handler.

**The mobile UI itself** (`Self.pageHTML`) is a single Swift raw string literal containing the full HTML/CSS/JS. To edit it:
- Plain vanilla JS, no frameworks. Global state lives in a handful of top-level `let`s (`D`, `bedData`, `bedScale`, etc.)
- The Beds tab (`#p-beds`) is **deliberately placed outside the `.content` div**, which has `max-width:480px` for the other three tabs. If you add new full-width mobile content, follow this pattern (sibling of `.content`, not a child)
- Bed grid zoom is fully custom (CSS `transform:scale()` driven by `bedScale`), not native browser zoom. Pinch-zoom anchors to the touch midpoint by adjusting `scrollLeft`/`scrollTop` in lockstep with the scale change
- After logging a planting to a bed, the JS calls `showTab('beds')` and `loadBed()` to navigate automatically. `showTab(name)` is a helper that finds the tab button by its `onclick` attribute and calls `show(name, btn)`

---

## Desktop bed grid zoom (`GardenBedPlannerView.swift`)

The desktop Garden Beds zoom is built on a custom `ZoomableScrollView<Content>: NSViewRepresentable` wrapping an `NSScrollView` + `NSHostingView`. This was necessary to anchor zooming to the cursor position — SwiftUI's built-in `MagnificationGesture` has no concept of "zoom around this screen point."

The anchor-point math (in `Coordinator`):
1. Convert the cursor's view-space point to *unscaled* content coordinates (divide by old zoom scale)
2. Apply the new zoom scale (mutates the `@Binding var zoomScale`)
3. In `updateNSView`, re-derive where that content point now lands on screen at the new scale, and set the clip view's scroll origin to put it back under the cursor

The two-step (`handleZoom` stages a `pendingAnchor`, `applyPendingAnchor` resolves it in `updateNSView`) is what keeps it smooth — doing the correction via `DispatchQueue.main.async` caused a visible one-frame jitter. If zoom becomes jittery, check whether something reintroduced an async hop between the scale change and the scroll correction.

---

## A SwiftUI layout gotcha worth knowing

`PlantingLogView`'s timeline once rendered vertically centred in its scroll area instead of pinned to the top. The cause: **giving content inside a two-axis `[.horizontal, .vertical]` `ScrollView` a `maxHeight: .infinity` frame** conflicts with how the scroll view determines its scrollable content size — the content ends up centred in the viewport regardless of alignment. The fix: use a concrete `minHeight` (from a sibling `GeometryReader`) plus a trailing `Spacer(minLength: 0)` inside a `VStack`. See `PlantingLogView.body` for the current implementation.

---

## Conventions to follow when extending the app

- **New persisted fields**: add as `Optional` to `AppDataFile`, with a sensible fallback in `load()`. Never assume an existing `garden.json` has the new field.
- **New mutations**: add a method on `AppData`; don't mutate model arrays directly from views if there's any side effect.
- **New mobile API endpoints**: add a case to `dispatch(...)` in `WebServer.swift`, with a small private `Decodable`/`Encodable` pair scoped to that handler; do the `AppData` work inside the main-thread-dispatch + semaphore pattern.
- **New mobile UI**: edit the JS/HTML inside `Self.pageHTML`. Keep new full-width content as a sibling of `.content`, not nested inside it.
- **Colour**: every seed has a `colorHex` used consistently for calendar bars, bed grid markers, and mobile bed cells — reuse it for any new visual representation of a seed.
- **`displayName`**: always prefer `seed.displayName` (name + variety) over `seed.name` alone in UI-facing text.

---

## Build verification

Run `./build-and-install.sh` after any change to verify the release build compiles cleanly and the app bundle launches correctly. For faster iteration during development, use Xcode (⌘R) — the CLI build catches Swift 6 concurrency violations that are easy to introduce when touching `WebServer.swift` or the `NSViewRepresentable` zoom code.
