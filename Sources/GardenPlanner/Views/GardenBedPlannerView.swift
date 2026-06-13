import SwiftUI
import UniformTypeIdentifiers

// Drag payload: seed UUID as string
struct SeedDragItem: Transferable {
    let seedId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: SeedDragItem.self, contentType: .seedDrag)
    }
}

extension SeedDragItem: Codable {}

extension UTType {
    static var seedDrag: UTType { UTType(exportedAs: "com.gardenplanner.seed") }
}

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
            VStack(alignment: .leading, spacing: 0) {
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

                Divider()

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
                .frame(maxHeight: 240)
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
        .draggable(SeedDragItem(seedId: seed.id))
        .cursor(.openHand)
    }
}

struct BedGridView: View {
    @Environment(AppData.self) private var appData
    let bed: GardenBed
    let year: Int

    let cellSize: CGFloat = 48

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Column header
                HStack(spacing: 1) {
                    Spacer().frame(width: 28)
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
                            .frame(width: 24)
                        ForEach(0..<bed.columns, id: \.self) { col in
                            let pos = GridPosition(row: row, column: col)
                            let cell = bed.cell(at: pos, year: year)
                            BedCellView(
                                cell: cell,
                                seed: cell.flatMap { appData.seed(id: $0.seedId) },
                                cellSize: cellSize
                            )
                            .dropDestination(for: SeedDragItem.self) { items, _ in
                                guard let item = items.first else { return false }
                                appData.plantSeed(item.seedId, in: bed.id, at: pos, year: year)
                                return true
                            }
                            .onTapGesture(count: 2) {
                                if cell != nil {
                                    appData.clearCell(in: bed.id, at: pos, year: year)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bed.name)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Label("Drag seeds from the panel onto cells", systemImage: "arrow.left")
                Text("·")
                Label("Double-click to clear", systemImage: "xmark")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}

struct BedCellView: View {
    let cell: BedCell?
    let seed: Seed?
    let cellSize: CGFloat
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(cellBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isTargeted ? 2 : 1)
                )

            if let seed = seed {
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
        }
        .frame(width: cellSize, height: cellSize)
        .dropDestination(for: SeedDragItem.self, action: { _, _ in false }, isTargeted: { isTargeted = $0 })
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
    @State private var columns = 4
    @State private var rows = 4
    @State private var squareSizeCm = 30.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Bed name", text: $name)
                Stepper("Columns: \(columns)", value: $columns, in: 1...30)
                Stepper("Rows: \(rows)", value: $rows, in: 1...30)
                LabeledContent("Square size (cm)") {
                    TextField("30", value: $squareSizeCm, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("New Garden Bed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let bed = GardenBed(name: name, columns: columns, rows: rows, squareSizeCm: squareSizeCm)
                        onAdd(bed)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 340, height: 250)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// macOS cursor modifier
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
