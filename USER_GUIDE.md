# GardenPlanner — User Guide

GardenPlanner is a macOS app for tracking your seeds, planning when to sow them, logging what you actually plant, and laying out your garden beds. Your data lives entirely on your Mac (`~/Documents/GardenPlanner/Data/garden.json`) — there's no cloud account, no sign-in, nothing leaves your computer unless you choose to access it from your phone (see [Mobile Access](#mobile-access-from-your-phone) below).

The app has four sections, listed in the sidebar on the left:

- **Seed Catalogue** — your seed inventory and reference info
- **Sowing Calendar** — a year-at-a-glance view of when to sow each seed
- **Planting Log** — a record of what you actually sowed and when
- **Garden Beds** — a map of your beds showing what's planted where

---

## Seed Catalogue

This is your master list of seeds. Each seed entry can hold:

- **Name and variety** (e.g. "Tomato" / "Gardener's Delight") — shown together as "Tomato (Gardener's Delight)" throughout the app
- **Supplier and website** — where you bought it
- **Seeds in stock** — a count you can edit by typing a number or using the +/- stepper
- **Use by date** — an optional expiry date
- **Sowing windows** — one or more date ranges (e.g. "Indoors" Feb–Mar, "Outdoors" May–Jun) used to build the Sowing Calendar. Each window can be a fixed date range or relative to your last/first frost dates (set in Settings)
- **Spacing, row spacing, depth, height, spread** — planting reference numbers. **Spread** is also used to draw a circle on the Garden Beds map showing how much room the mature plant needs
- **Germination temperature range**
- **Days to germination / days to harvest**
- **Sun requirement, companion/antagonist plants, notes, tags**
- **A colour** — used as that seed's colour everywhere else in the app (calendar bars, bed markers, etc.)

Selecting a seed in the list shows its detail view on the right, including its **Planting History** — every Planting Log entry for that seed, with the location and outcome.

When you log a planting (see Planting Log below), the seed's "Seeds in stock" count is automatically reduced by the quantity sown.

---

## Sowing Calendar

A grid with one row per seed and the months of the year across the top. Each row shows a coloured bar for every sowing window defined on that seed (e.g. a green bar for "Outdoors", an orange bar for "Indoors"), positioned across the months it covers.

**Small dots overlaid on each bar show your actual sowing dates** pulled from the Planting Log for the current year — so you can see at a glance whether you sowed on time, early, or late relative to the recommended window. Hover a dot to see the exact date and quantity sown.

Controls:
- **Today** button — filters the calendar to seeds sowable today
- **Filter by date** — pick any date to see which seeds have a window covering it
- **Drag the divider** between the plant name column and the calendar to resize it

---

## Planting Log

Shows one row per seed that has plantings recorded for the selected year, with a small marker plotted on a year-long timeline for each time you sowed it. This lets you see at a glance how many times you sowed a seed and when, all on one row, rather than scrolling a long list.

- **Year** picker at the top switches between years
- **Search field** (top right) filters rows by seed name
- **Click a marker** to open that planting's full details in the panel on the right — sowing date, location, quantity, transplant/harvest dates, outcome, and notes. You can edit any of these fields directly
- **Right-click a marker** for a quick "Delete" option, or use the **Delete Record** button in the detail panel
- **Log Planting** button (top right) adds a new entry — pick the seed, date sown, location, and quantity. Locations can be one of your Garden Beds, or a custom location (e.g. "Greenhouse", "Cold frame") which you can add on the fly with the **+** button next to the location picker

Logging a planting automatically deducts the quantity from that seed's stock count in the Seed Catalogue.

---

## Garden Beds

A map view of each garden bed as a grid of squares, sized according to the bed's physical dimensions and "square size" (set when you create the bed).

- **Add a bed**: gives it a name, width, length, and square size (default 30cm) — the app works out the grid dimensions for you
- **Plant a seed**: drag a seed from the palette on the left onto a cell, or right-click a cell and choose "Plant seed here"
- **Move a planting**: drag an already-planted cell to a new cell
- **Clear a cell**: double-click it, or right-click and choose "Clear cell"
- Each planted cell shows the seed's colour, name (with variety), and — if the seed has a **spread** value set in the catalogue — a lightly shaded circle showing how much space the mature plant will need, which can extend beyond the cell into neighbours
- Each cell also shows its **distance in centimetres** from the bed's top-left corner in small grey text, top-left of the cell — handy for measuring out the bed with a tape measure
- **Zoom**: pinch on the trackpad, hold ⌘ and scroll the mouse wheel, or use the +/− buttons in the toolbar. Zooming anchors to wherever your cursor is, like Maps
- The seed list and bed list in the sidebar share the space 50:50 — drag the splitter between them to resize

---

## Settings

Open via the app menu (GardenPlanner → Settings, or ⌘,).

- **Frost Dates** — your last spring frost and first autumn frost dates. These are used to resolve any "frost-relative" sowing windows (e.g. "2 weeks after last frost") in the Seed Catalogue
- **Mobile Web Access** — turns the built-in web server on/off, lets you set the port, shows whether it's running, and lists the URLs to use from your phone (see below)
- **Data location** — shows where your data file lives, with a button to reveal it in Finder

---

## Mobile Access (from your phone)

Sowing and transplanting happens outdoors, away from your computer — GardenPlanner can serve a simple mobile-friendly web page so you can log plantings and update your garden beds from your phone, without needing an iPhone or any app installed on the phone.

### One-time setup

1. Make sure your Mac and your phone are both on the same [Tailscale](https://tailscale.com) network (a free VPN mesh — install the Tailscale app on your phone and sign in with the same account used on your Mac)
2. In GardenPlanner, open **Settings → Mobile Web Access** and make sure **Enable web server** is on
3. Under "Access URLs", copy the one starting with `100.` (that's your Mac's Tailscale address) — tap the copy icon next to it
4. On your phone, open that URL in your browser and bookmark it

### Using it

The mobile page has four tabs:
- **Log** — log a new planting (seed, date, location, quantity)
- **Transplant** — mark an existing planting as transplanted
- **Seeds** — browse your seed catalogue and stock levels
- **Beds** — tap a bed to see its grid; tap an empty square to plant a seed, tap a planted square to clear it. Pinch or use the +/− buttons to zoom in on a bed; each cell shows its distance in cm from the bed's corner, same as on the desktop

Anything you do on your phone is saved straight into the same `garden.json` file the desktop app uses — there's no separate "sync" step.

### Keeping the connection alive

Mac laptops go to sleep after a period of inactivity, which will disconnect the mobile page. GardenPlanner has a **"Keep Mac awake while serving"** toggle in Settings → Mobile Web Access (on by default) that stops the Mac going to idle sleep while the web server is running. Two things it can't do:
- It won't stop the screen from dimming/sleeping (that's fine — the server keeps running)
- It won't stop the Mac sleeping if you **close the lid** — for that, either keep the lid open, plug in an external display, or check System Settings → Lock Screen/Battery for an option to prevent sleep while on power

If the mobile page ever shows "Could not load" or won't connect, check Settings → Mobile Web Access on the Mac: the status indicator should be green/"Running". If it's red, click **Retry**, and check the error message shown (e.g. another app may be using the same port — try changing the port number).

---

## Data & Backups

All your data is stored in a single file:

```
~/Documents/GardenPlanner/Data/garden.json
```

This is plain JSON, so it's easy to back up (e.g. include it in your regular Mac backup, or copy it somewhere safe periodically) or move to another Mac. Use **Settings → Reveal in Finder** to find it quickly.
