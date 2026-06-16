import SwiftUI
import AppKit


struct GardenBedPlannerView: View {
    @Environment(AppData.self) private var appData
    @State private var selectedBedId: UUID?
    @State private var showingAddBedSheet = false
    @State private var planYear = Calendar.current.component(.year, from: Date())

    var selectedBed: GardenBed? {
        appData.gardenBeds.first { $0.id == selectedBedId }
    }

    var body: some View {
        NavigationSplitView {
            VSplitView {
                List(appData.gardenBeds, selection: $selectedBedId) { bed in
                    Label(bed.name, systemImage: "rectangle.split.3x3")
                        .tag(bed.id)
                        .contextMenu {
                            Button("Delete Bed", role: .destructive) {
                                appData.deleteBed(id: bed.id)
                                if selectedBedId == bed.id { selectedBedId = nil }
                            }
                        }
                }
                .navigationTitle("Garden Beds")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddBedSheet = true } label: {
                            Label("Add Bed", systemImage: "plus")
                        }
                    }
                }
                .frame(minHeight: 80)

                // Seed palette for dragging
                VStack(alignment: .leading, spacing: 6) {
                    Text("Seeds").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 8)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(appData.seeds.sorted { $0.displayName < $1.displayName }) { seed in
                                SeedPaletteRow(seed: seed)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
                .frame(minHeight: 80)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let bed = selectedBed {
                BedGridView(bed: bed, year: planYear)
                    .toolbar {
                        ToolbarItem {
                            Picker("Year", selection: $planYear) {
                                ForEach(Array((planYear-2)...(planYear+2)), id: \.self) { Text(String($0)).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
            } else {
                ContentUnavailableView("Select a Bed", systemImage: "square.grid.3x3", description: Text("Choose a bed or add a new one."))
            }
        }
        .sheet(isPresented: $showingAddBedSheet) {
            AddBedView { newBed in
                appData.addBed(newBed)
                selectedBedId = newBed.id
            }
        }
    }
}

struct SeedPaletteRow: View {
    let seed: Seed

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: seed.colorHex))
                .frame(width: 10, height: 10)
            Text(seed.displayName)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .draggable(seed.id.uuidString)
        .cursor(.openHand)
    }
}

struct BedGridView: View {
    @Environment(AppData.self) private var appData
    let bed: GardenBed
    let year: Int

    let baseCellSize: CGFloat = 48
    @State private var zoomScale: CGFloat = 1.0

    var cellSize: CGFloat { baseCellSize * zoomScale }

    var body: some View {
        ZoomableScrollView(zoomScale: $zoomScale, minZoom: 0.4, maxZoom: 2.5) {
            gridContent
        }
        .navigationTitle(bed.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { zoomScale = max(0.4, zoomScale - 0.1) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom out")
                Button("Reset") { zoomScale = 1.0 }
                Button { zoomScale = min(2.5, zoomScale + 0.1) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Label("Right-click a cell to plant a seed", systemImage: "computermouse")
                Text("·")
                Label("Or drag from the seed list on the left", systemImage: "arrow.left")
                Text("·")
                Label("Double-click to clear", systemImage: "xmark")
                Text("·")
                Label("Pinch or ⌘-scroll over the grid to zoom", systemImage: "magnifyingglass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    var gridContent: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Column header
                HStack(spacing: 1) {
                    Spacer().frame(width: 28 * zoomScale)
                    ForEach(0..<bed.columns, id: \.self) { col in
                        Text("\(col + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize)
                    }
                }
                .padding(.bottom, 2)

                // Grid rows
                ForEach(0..<bed.rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        Text("\(row + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 24 * zoomScale)
                        ForEach(0..<bed.columns, id: \.self) { col in
                            let pos = GridPosition(row: row, column: col)
                            let cell = bed.cell(at: pos, year: year)
                            let plantedSeed = cell.flatMap { appData.seed(id: $0.seedId) }
                            BedCellView(
                                cell: cell,
                                seed: plantedSeed,
                                cellSize: cellSize,
                                squareSizeCm: bed.squareSizeCm,
                                row: row,
                                column: col,
                                allSeeds: appData.seeds,
                                onDrop: { payload in
                                    // Payload is either "UUID" (from palette) or "UUID|row|col" (from cell)
                                    let parts = payload.split(separator: "|")
                                    guard let seedId = UUID(uuidString: String(parts[0])) else { return }
                                    if parts.count == 3,
                                       let srcRow = Int(parts[1]),
                                       let srcCol = Int(parts[2]) {
                                        let srcPos = GridPosition(row: srcRow, column: srcCol)
                                        if srcPos != pos {
                                            appData.clearCell(in: bed.id, at: srcPos, year: year)
                                        }
                                    }
                                    appData.plantSeed(seedId, in: bed.id, at: pos, year: year)
                                },
                                onClear: { appData.clearCell(in: bed.id, at: pos, year: year) },
                                onPlant: { seedId in appData.plantSeed(seedId, in: bed.id, at: pos, year: year) },
                                dragPayload: cell.map { "\($0.seedId.uuidString)|\($0.row)|\($0.column)" }
                            )
                        }
                    }
                }
            }
            .padding()
    }
}

// MARK: - Cursor-anchored zoomable scroll view

private class ZoomTrackingScrollView: NSScrollView {
    var onZoom: ((CGFloat, NSPoint) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let location = convert(event.locationInWindow, from: nil)
            onZoom?(event.scrollingDeltaY * 0.003, location)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onZoom?(event.magnification, location)
    }
}

struct ZoomableScrollView<Content: View>: NSViewRepresentable {
    @Binding var zoomScale: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ZoomTrackingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let hosting = NSHostingView(rootView: content())
        scrollView.documentView = hosting
        hosting.frame.size = hosting.fittingSize
        context.coordinator.hostingView = hosting
        context.coordinator.scrollView = scrollView

        scrollView.onZoom = { [coordinator = context.coordinator] delta, location in
            coordinator.handleZoom(delta: delta, locationInView: location)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hosting = context.coordinator.hostingView else { return }
        hosting.rootView = content()
        hosting.frame.size = hosting.fittingSize
        context.coordinator.applyPendingAnchor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale, minZoom: minZoom, maxZoom: maxZoom)
    }

    final class Coordinator {
        @Binding var zoomScale: CGFloat
        let minZoom: CGFloat
        let maxZoom: CGFloat
        weak var hostingView: NSHostingView<Content>?
        weak var scrollView: NSScrollView?
        private var pendingAnchor: (unscaledPoint: NSPoint, locationInView: NSPoint, newScale: CGFloat)?

        init(zoomScale: Binding<CGFloat>, minZoom: CGFloat, maxZoom: CGFloat) {
            _zoomScale = zoomScale
            self.minZoom = minZoom
            self.maxZoom = maxZoom
        }

        @MainActor func handleZoom(delta: CGFloat, locationInView: NSPoint) {
            guard let scrollView = scrollView else { return }
            let oldScale = zoomScale
            let newScale = min(maxZoom, max(minZoom, oldScale * (1 + delta)))
            guard newScale != oldScale else { return }

            let clipView = scrollView.contentView
            let originBefore = clipView.bounds.origin
            let pointBefore = NSPoint(x: originBefore.x + locationInView.x, y: originBefore.y + locationInView.y)
            let unscaledPoint = NSPoint(x: pointBefore.x / oldScale, y: pointBefore.y / oldScale)

            pendingAnchor = (unscaledPoint, locationInView, newScale)
            zoomScale = newScale
        }

        @MainActor func applyPendingAnchor() {
            guard let anchor = pendingAnchor, let scrollView = scrollView else { return }
            pendingAnchor = nil
            let clipView = scrollView.contentView
            let pointAfter = NSPoint(x: anchor.unscaledPoint.x * anchor.newScale, y: anchor.unscaledPoint.y * anchor.newScale)
            let newOrigin = NSPoint(x: pointAfter.x - anchor.locationInView.x, y: pointAfter.y - anchor.locationInView.y)
            clipView.scroll(to: newOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

struct BedCellView: View {
    let cell: BedCell?
    let seed: Seed?
    let cellSize: CGFloat
    let squareSizeCm: Double
    let row: Int
    let column: Int
    let allSeeds: [Seed]
    let onDrop: (String) -> Void
    let onClear: () -> Void
    let onPlant: (UUID) -> Void
    let dragPayload: String?
    @State private var isTargeted = false

    var spreadDiameter: CGFloat? {
        guard let spread = seed?.spreadCm, squareSizeCm > 0 else { return nil }
        return CGFloat(spread / squareSizeCm) * cellSize
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(cellBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isTargeted ? 2 : 1)
                )

            if let seed = seed {
                // Spread circle — may extend beyond cell bounds
                if let diameter = spreadDiameter {
                    Circle()
                        .fill(Color(hex: seed.colorHex).opacity(0.12))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(hex: seed.colorHex).opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: diameter, height: diameter)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 2) {
                    Circle()
                        .fill(Color(hex: seed.colorHex))
                        .frame(width: 14, height: 14)
                    Text(seed.name)
                        .font(.system(size: 8))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
                .padding(4)
            }

            VStack {
                HStack {
                    Text("\(Int((Double(column) * squareSizeCm).rounded())),\(Int((Double(row) * squareSizeCm).rounded()))")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                        .padding(.top, 1)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .frame(width: cellSize, height: cellSize)
        .modifier(DraggableIfNeeded(payload: seed != nil ? dragPayload : nil))
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            onDrop(payload)
            return true
        } isTargeted: { isTargeted = $0 }
        .onTapGesture(count: 2) {
            if cell != nil { onClear() }
        }
        .contextMenu {
            Menu("Plant seed here") {
                ForEach(allSeeds.sorted { $0.displayName < $1.displayName }) { s in
                    Button(s.displayName) { onPlant(s.id) }
                }
            }
            if cell != nil {
                Divider()
                Button("Clear cell", role: .destructive) { onClear() }
            }
        }
    }

    var cellBackground: Color {
        if isTargeted { return .accentColor.opacity(0.15) }
        if seed != nil { return Color(hex: seed!.colorHex).opacity(0.18) }
        return Color.primary.opacity(0.04)
    }
}

struct AddBedView: View {
    @Environment(\.dismiss) var dismiss
    var onAdd: (GardenBed) -> Void

    @State private var name = ""
    @State private var widthCm = 120.0
    @State private var lengthCm = 240.0
    @State private var squareSizeCm = 30.0

    var columns: Int { max(1, Int((lengthCm / squareSizeCm).rounded())) }
    var rows: Int    { max(1, Int((widthCm / squareSizeCm).rounded())) }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Garden Bed")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Bed name") {
                    TextField("e.g. Raised Bed 1", text: $name)
                }
                LabeledContent("Width (cm)") {
                    TextField("120", value: $widthCm, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                LabeledContent("Length (cm)") {
                    TextField("240", value: $lengthCm, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                LabeledContent("Square size (cm)") {
                    TextField("30", value: $squareSizeCm, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                Divider()
                HStack {
                    Image(systemName: "squareshape.split.2x2")
                        .foregroundStyle(.secondary)
                    Text("\(columns) × \(rows) grid (\(columns * rows) squares)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    let bed = GardenBed(name: name, columns: columns, rows: rows, squareSizeCm: squareSizeCm)
                    onAdd(bed)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || squareSizeCm <= 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 380, height: 320)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

struct DraggableIfNeeded: ViewModifier {
    let payload: String?
    func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload).cursor(.openHand)
        } else {
            content
        }
    }
}
