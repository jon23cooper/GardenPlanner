# GardenPlanner — Developer Guide

GardenPlanner is a native macOS app built with **SwiftUI** and the **Swift Package Manager** (no `.xcodeproj`/`.xcworkspace` — Xcode opens the `Package.swift` directly). It targets macOS 14+ and uses Swift 6 with strict concurrency checking.

For what the app does from a user's perspective, see [USER_GUIDE.md](USER_GUIDE.md).

---

## Project layout

```
Package.swift
Sources/GardenPlanner/
  GardenPlannerApp.swift        — @main entry point, WindowGroup + Settings scene
  AppData.swift                 — single @Observable model: state, persistence, web server lifecycle
  WebServer.swift                — embedded HTTP server + mobile web UI (HTML/CSS/JS as a Swift string)
  Info.plist                    — linked into the binary manually (see "Linker quirk" below)
  Models/
    Seed.swift                  — Seed, SowingWindow, SowDateSpec, SunRequirement
    PlantingRecord.swift        — PlantingRecord, PlantLocation, Outcome, GridPosition
    GardenBed.swift              — GardenBed, BedCell
  Views/
    ContentView.swift            — top-level NavigationSplitView + sidebar section switch
    SeedCatalogView.swift        — seed list/detail/edit
    SowingCalendarView.swift     — year calendar grid + Planting Log overlay dots
    PlantingLogView.swift        — per-seed sowing timeline + record detail inspector
    GardenBedPlannerView.swift   — bed grid, drag/drop planting, cursor-anchored zoom
    SettingsView.swift           — frost dates, mobile web access, data location
```

There is no test target yet.

---

## Building and running

Xcode on this machine is at a non-standard path (system Xcode is broken on the current macOS), so builds must point at it explicitly:

```bash
DEVELOPER_DIR=/Volumes/ORICO/Applications/Xcode.app/Contents/Developer \
  /Volumes/ORICO/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift build
```

Run the built binary directly, or open the package folder in Xcode and use ⌘R (the user develops this way day-to-day; Xcode's build lives in `DerivedData`, completely separate from `swift build`'s `.build/debug` — **rebuilding via the CLI does not update what's running from Xcode, and vice versa**. If you've made a change and a behaviour doesn't seem to have taken effect, check which binary is actually running before assuming the code is wrong).

There's no Xcode project file checked in; Xcode treats `Package.swift` as the project when opened directly.

---

## Linker quirk: Info.plist

Since this is a plain SwiftPM executable (not an `.app` bundle target), `Info.plist` isn't picked up automatically. `Package.swift` manually links it into the `__TEXT,__info_plist` section via `unsafeFlags`. This is what allows `NSApp.setActivationPolicy(.regular)` (in `GardenPlannerApp.swift`) to make the binary behave like a normal foreground app with a Dock icon and menu bar, instead of a headless command-line tool.

---

## Data model and persistence

`AppData` (`AppData.swift`) is the single source of truth — an `@Observable` class injected into the SwiftUI environment from `GardenPlannerApp`. All collections (`seeds`, `plantingRecords`, `gardenBeds`, `customLocations`, frost dates, web server settings) use `didSet { save() }` so any mutation anywhere in the app immediately persists to disk:

```
~/Documents/GardenPlanner/Data/garden.json
```

`save()`/`load()` go through a private `AppDataFile: Codable` struct. **All fields added after the initial version are `Optional` with `?? defaultValue` fallbacks in `load()`** — this is the established pattern for schema evolution; never make a new field non-optional without a migration path, since old `garden.json` files won't have it.

`PlantLocation` (in `PlantingRecord.swift`) is a hand-written `Codable` enum that supports two on-disk shapes:
- New format: `{"type": "bed"|"custom", "id": ..., "name": ...}`
- Legacy format: a bare string (from before `PlantLocation` existed, when locations were a fixed `SowLocation` enum)

`init(from:)` tries the new keyed format first and falls back to a plain string decode. Follow this same try/fallback pattern if you need to change any other model's wire format — don't just change the shape and hope old data still loads.

Mutating methods on `AppData` (`addSeed`, `plantSeed`, `clearCell`, `addPlantingRecord`, etc.) are the only places that should mutate the model collections — views bind through `@Bindable`/`$appData.x` for in-place edits (e.g. `PlantingRecordDetailView`), but anything with side effects (stock deduction, replacing a bed cell) goes through an `AppData` method so the logic lives in one place. Notably, `addPlantingRecord` also decrements the seed's `quantityPackets` — if you add another place that logs a planting (e.g. a new API endpoint), route it through this method rather than appending to `plantingRecords` directly, or stock tracking will silently drift.

---

## The embedded web server (`WebServer.swift`)

This is the most unusual part of the codebase, so it's worth understanding before touching it.

**Why it exists:** the user wanted to log plantings from an Android phone while standing in the garden. Rather than building a second client or a sync backend, the app serves its own data as a small mobile web page over the local network (reached via Tailscale from outside the LAN).

**Why raw POSIX sockets, not `Network.framework`:** an earlier version used `NWListener`, which proved unreliable in practice (state machine sometimes never reached `.ready`, server showed as "Stopped" in Settings with no clear cause). It was replaced with a `final class WebServer: @unchecked Sendable` built directly on `socket()`/`bind()`/`listen()`/`accept()`/`read()`/`write()` from Darwin. If you're tempted to "modernise" this back to `Network.framework`, be aware of why it was moved away from — test thoroughly under real network conditions (sleep/wake, port conflicts, Tailscale reconnects) before doing so.

**Threading model:** `acceptLoop()` and `handleClient(_:)` run on a background `DispatchQueue`. Because `AppData` must only be touched on the main thread (it's `@Observable` and drives SwiftUI), each request's actual data work is dispatched to `.main` and the socket thread blocks on a `DispatchSemaphore` until it's done. The result is handed back across threads via a small `final class Box: @unchecked Sendable { var data = Data() }` wrapper — Swift 6's strict concurrency checker can't prove this handoff is safe, so the `@unchecked Sendable` annotations are deliberate, not oversights. Keep new endpoints inside this same `dispatch(...)` → main-thread-closure → semaphore pattern; don't touch `appData` from the accept/read/write code directly.

**Routing:** `dispatch(method:path:body:appData:)` is a simple manual switch over `(method, path)` — there's no router abstraction. `GET /` and `/index.html` serve the entire mobile UI as one big string (`Self.pageHTML`); everything else under `/api/...` is JSON in, JSON out, hand-decoded with small private `Decodable`/`Encodable` structs scoped inside each handler function (see `apiBedData`, `apiPlant`, etc.) rather than reusing the app's main models directly — this keeps the wire format decoupled from internal model changes, at the cost of needing to update both sides when you add a field (e.g. `spreadCm`/`squareSizeCm` were added to `apiBedData`'s `CellOut`/`Out` structs specifically to support the spread-circle and cm-distance features, mirroring fields already on `Seed`/`GardenBed`).

**The mobile UI itself** (`Self.pageHTML`) is a single Swift raw string literal (`#"""..."""#`) containing the full HTML/CSS/JS — there's no build step, bundler, or separate web project. To edit it:
- It's plain vanilla JS, no frameworks. Global state lives in a handful of top-level `let`s (`D` = cached `/api/data` response, `bedData`, `bedScale`, etc.)
- `load()` fetches `/api/data` and calls `render()`, which fans out to `renderLog()`, `renderTransplant()`, `renderSeeds()`, `renderBedSelectors()`
- The Beds tab (`#p-beds`) is **deliberately placed outside the `.content` div**, which has `max-width:480px` for the other three tabs — this was a fix for the bed grid not expanding to fill width in landscape. If you add new full-width mobile content, follow this same pattern (sibling of `.content`, not a child) rather than fighting the width constraint with margins
- Bed grid zoom is fully custom (CSS `transform:scale()` driven by a JS `bedScale` variable), not native browser/viewport zoom — native zoom proved unreliable across Android browsers. Pinch-zoom anchors to the touch midpoint by adjusting `scrollLeft`/`scrollTop` in lockstep with the scale change (see the `touchmove` handler) — if you ever see pinch-zoom "jump" or zoom from the wrong point, this is the math to check first
- `touch-action` on the scrollable wrapper must stay permissive (no blanket `touch-action:none`) or single-finger scrolling breaks; the pinch handlers already scope their `e.preventDefault()` to two-finger touches only

---

## Desktop bed grid zoom (`GardenBedPlannerView.swift`)

The desktop Garden Beds zoom is built on a custom `ZoomableScrollView<Content>: NSViewRepresentable` wrapping an `NSScrollView` + `NSHostingView`, rather than SwiftUI's `ScrollView` + `MagnificationGesture`. This was necessary to anchor zooming to the cursor position (like Maps) — SwiftUI's built-in gesture has no concept of "zoom around this screen point and keep it stationary," so a custom `NSScrollView` subclass (`ZoomTrackingScrollView`) intercepts `scrollWheel(with:)` (when ⌘ is held) and `magnify(with:)`, and the `Coordinator` does the anchor-point math:

1. Convert the cursor's view-space point to a point in *unscaled* content coordinates (divide by the old zoom scale)
2. Apply the new zoom scale (mutates the `@Binding var zoomScale`, which SwiftUI re-renders from)
3. In `updateNSView` (called once the new `rootView`/size has been set), re-derive the screen point for that same unscaled content point at the *new* scale, and set the clip view's scroll origin so it lands back under the cursor

This two-step (`handleZoom` stages a "pending anchor," `applyPendingAnchor` resolves it during the next `updateNSView`) is what keeps it smooth — doing the scroll correction via `DispatchQueue.main.async` after the zoom change was tried first and caused a visible one-frame jitter on every scroll tick; doing it synchronously within the same `updateNSView` pass fixed that. If you touch this code and zoom becomes jittery again, check whether something reintroduced an async hop between the scale change and the scroll correction.

If you need similar Maps-style zoom elsewhere, this `ZoomableScrollView` is generic over its `Content` and could be reused as-is.

---

## A SwiftUI layout gotcha worth knowing

`PlantingLogView`'s timeline once rendered vertically centered in its scroll area instead of pinned to the top, even after several attempts using `.frame(maxHeight: .infinity, alignment: .top)`. The actual fix: **don't give content inside a two-axis (`[.horizontal, .vertical]`) `ScrollView` a `maxHeight: .infinity` frame** — it conflicts with how the scroll view determines its own scrollable content size and the content ends up centered in the viewport regardless of the alignment parameter. The working pattern is to use a concrete `minHeight` (from a sibling `GeometryReader`'s measured size) plus a trailing `Spacer(minLength: 0)` inside a `VStack`, which is the idiomatic SwiftUI way to pin shorter-than-viewport content to the top of a scroll view. See `PlantingLogView.body` for the current implementation if you need the same trick elsewhere.

---

## Conventions to follow when extending the app

- **New persisted fields**: add as `Optional` to `AppDataFile`, with a sensible fallback in `load()`. Never assume an existing `garden.json` has the new field.
- **New mutations**: add a method on `AppData`, don't mutate `appData.seeds`/`appData.plantingRecords`/`appData.gardenBeds` arrays directly from a view if there's any side effect involved (stock deduction, cross-collection consistency).
- **New mobile API endpoints**: add a case to `dispatch(...)` in `WebServer.swift`, with a small private `Decodable`/`Encodable` pair scoped to that handler; do the actual `AppData` work inside the existing main-thread-dispatch + semaphore pattern.
- **New mobile UI**: edit the JS/HTML inside `Self.pageHTML`. Keep new full-width content as a sibling of `.content`, not nested inside it.
- **Colour**: every seed has a `colorHex` used consistently for its calendar bars, bed grid markers/circles, and mobile bed cells — if you add a new visual representation of a seed, reuse `colorHex` rather than picking a new colour scheme.
- **`displayName`**: always prefer `seed.displayName` (name + variety) over `seed.name` alone in any UI-facing text; `seed.name` should really only be used for raw data entry/editing.

---

## Build verification

There's no automated test suite — verify changes by building and exercising them manually (in the running app and, for `WebServer.swift` changes, in a phone/desktop browser against the running server). Always run a `swift build` after editing before considering a change done; the CLI build is fast (a few seconds) and catches Swift 6 concurrency violations (e.g. missing `@MainActor`, non-`Sendable` capture) that are easy to introduce when touching `WebServer.swift` or the `NSViewRepresentable` zoom code.
