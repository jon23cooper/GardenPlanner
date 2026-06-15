import SwiftUI

struct SeedCatalogView: View {
    @Environment(AppData.self) private var appData
    @State private var searchText = ""
    @State private var selectedSeed: Seed?
    @State private var showingAddSheet = false
    @State private var sortOrder = SortOrder.name

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case dateAdded = "Recently Added"
    }

    var filteredSeeds: [Seed] {
        let base = appData.seeds.filter {
            searchText.isEmpty ||
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.variety.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
        switch sortOrder {
        case .name: return base.sorted { $0.displayName < $1.displayName }
        case .dateAdded: return base
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredSeeds, selection: $selectedSeed) { seed in
                SeedRowView(seed: seed)
                    .tag(seed)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            appData.deleteSeed(id: seed.id)
                            if selectedSeed?.id == seed.id { selectedSeed = nil }
                        }
                    }
            }
            .searchable(text: $searchText, prompt: "Search seeds…")
            .navigationTitle("Seed Catalogue")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddSheet = true } label: {
                        Label("Add Seed", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
        } detail: {
            if let seed = selectedSeed, let idx = appData.seeds.firstIndex(where: { $0.id == seed.id }) {
                @Bindable var bindableData = appData
                SeedDetailView(seed: $bindableData.seeds[idx])
                    .id(seed.id)
            } else {
                ContentUnavailableView("Select a Seed", systemImage: "leaf", description: Text("Choose a seed from the list to view details."))
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSeedView { newSeed in
                appData.addSeed(newSeed)
                selectedSeed = newSeed
            }
        }
    }
}

struct SeedRowView: View {
    let seed: Seed

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: seed.colorHex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(seed.name).fontWeight(.medium)
                if !seed.variety.isEmpty {
                    Text(seed.variety).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if seed.quantityPackets == 0 {
                Text("Out of stock")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
            }
        }
    }
}

struct SeedDetailView: View {
    @Binding var seed: Seed
    @Environment(AppData.self) private var appData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        TextField("Name", text: $seed.name)
                            .font(.title).fontWeight(.bold)
                        TextField("Variety", text: $seed.variety)
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorPickerField(colorHex: $seed.colorHex)
                }

                Divider()

                // Stock & supplier
                GroupBox("Stock & Supplier") {
                    LabeledContent("Supplier") {
                        TextField("Supplier name", text: $seed.supplier)
                    }
                    LabeledContent("Website") {
                        HStack(spacing: 6) {
                            TextField("https://", text: $seed.url)
                            if let url = URL(string: seed.url), !seed.url.isEmpty, url.scheme != nil {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .help("Open in browser")
                            }
                        }
                    }
                    LabeledContent("Packets in stock") {
                        Stepper("\(seed.quantityPackets)", value: $seed.quantityPackets, in: 0...999)
                    }
                }

                // Sowing windows
                SowingWindowsEditor(windows: $seed.sowingWindows)

                // Growing info
                GroupBox("Growing") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Sun requirement") {
                            Picker("", selection: $seed.sunRequirement) {
                                ForEach(SunRequirement.allCases, id: \.self) { Text($0.rawValue) }
                            }.labelsHidden()
                        }
                        OptionalDoubleField(label: "Plant spacing (cm)", value: $seed.spacingCm)
                        OptionalDoubleField(label: "Row spacing (cm)", value: $seed.rowSpacingCm)
                        OptionalDoubleField(label: "Sow depth (cm)", value: $seed.depthCm)
                        OptionalDoubleField(label: "Height (cm)", value: $seed.heightCm)
                        OptionalDoubleField(label: "Spread (cm)", value: $seed.spreadCm)
                        OptionalRangeField(label: "Days to germination", range: $seed.daysToGermination)
                        OptionalRangeField(label: "Days to harvest", range: $seed.daysToHarvest)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Companions
                GroupBox("Companion Planting") {
                    TagListField(label: "Good companions", tags: $seed.companions, accentColor: .green)
                    TagListField(label: "Avoid planting near", tags: $seed.antagonists, accentColor: .red)
                }

                // Tags & notes
                GroupBox("Notes & Tags") {
                    TagListField(label: "Tags", tags: $seed.tags, accentColor: .blue)
                    TextEditor(text: $seed.notes)
                        .frame(minHeight: 80)
                        .font(.body)
                }

                // Planting history
                let history = appData.plantingRecords(for: seed.id)
                if !history.isEmpty {
                    GroupBox("Planting History") {
                        ForEach(history) { record in
                            HStack {
                                Text(record.dateSown, format: .dateTime.day().month().year())
                                Text(record.location.rawValue).foregroundStyle(.secondary)
                                Spacer()
                                Text(record.outcome.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(outcomeColor(record.outcome))
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding()
        }
    }

    func outcomeColor(_ outcome: Outcome) -> Color {
        switch outcome {
        case .success: return .green
        case .partialSuccess: return .orange
        case .failure: return .red
        case .ongoing: return .secondary
        }
    }
}

// MARK: - Field helpers

struct ColorPickerField: View {
    @Binding var colorHex: String
    @State private var showingPopover = false
    let palette = ["#4CAF50","#8BC34A","#FF9800","#F44336","#9C27B0","#2196F3","#FFEB3B","#795548","#607D8B","#E91E63"]

    var body: some View {
        Button { showingPopover = true } label: {
            Circle().fill(Color(hex: colorHex)).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                ForEach(palette, id: \.self) { hex in
                    ZStack {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                        if colorHex == hex {
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .frame(width: 24, height: 24)
                            Circle()
                                .strokeBorder(.primary.opacity(0.4), lineWidth: 1)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .onTapGesture {
                        colorHex = hex
                        showingPopover = false
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Sowing Windows Editor

struct SowingWindowsEditor: View {
    @Binding var windows: [SowingWindow]

    let suggestedLabels = ["Indoors", "Outdoors", "Spring", "Autumn", "Greenhouse", "Direct sow"]
    let palette = ["#4CAF50","#8BC34A","#FF9800","#F44336","#9C27B0","#2196F3","#FFEB3B","#795548","#607D8B","#E91E63"]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($windows) { $window in
                    HStack(alignment: .top, spacing: 8) {
                        SowingWindowRow(window: $window)
                        Button(role: .destructive) {
                            windows.removeAll { $0.id == window.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    Divider()
                }

                Button {
                    windows.append(SowingWindow(
                        label: suggestedLabel(),
                        colorHex: palette[windows.count % palette.count]
                    ))
                } label: {
                    Label("Add Sowing Window", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        } label: {
            Text("Sowing Windows")
        }
    }

    func suggestedLabel() -> String {
        let existing = Set(windows.map { $0.label })
        return suggestedLabels.first { !existing.contains($0) } ?? "Window \(windows.count + 1)"
    }
}

struct SowingWindowRow: View {
    @Binding var window: SowingWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label + colour
            HStack {
                ColorPickerField(colorHex: $window.colorHex)
                TextField("Label", text: $window.label)
                    .fontWeight(.medium)
                Spacer()
            }

            // Start date
            SowDateSpecRow(label: "From", spec: $window.start)
            // End date
            SowDateSpecRow(label: "To", spec: $window.end)
        }
        .padding(.vertical, 4)
    }
}

struct SowDateSpecRow: View {
    let label: String
    @Binding var spec: SowDateSpec

    private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Picker("", selection: $spec.kind) {
                Text("Fixed date").tag(SowDateSpec.Kind.fixed)
                Text("Frost relative").tag(SowDateSpec.Kind.frostRelative)
            }
            .labelsHidden()
            .frame(width: 130)

            if spec.kind == .fixed {
                Picker("", selection: $spec.month) {
                    ForEach(1...12, id: \.self) { Text(monthNames[$0 - 1]).tag($0) }
                }
                .labelsHidden()
                .frame(width: 70)

                Picker("", selection: $spec.day) {
                    ForEach(1...31, id: \.self) { Text(String($0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 55)
            } else {
                HStack(spacing: 4) {
                    Stepper(value: $spec.weeksFromFrost, in: -52...52) {
                        let abs = abs(spec.weeksFromFrost)
                        let dir = spec.weeksFromFrost < 0 ? "before" : (spec.weeksFromFrost == 0 ? "at" : "after")
                        Text("\(abs)w \(dir) frost")
                            .font(.callout)
                            .frame(width: 120, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Legacy field (kept for any remaining uses)

struct OptionalIntField: View {
    let label: String
    let hint: String
    @Binding var value: Int?
    @State private var text = ""
    @State private var enabled = false

    var body: some View {
        LabeledContent(label) {
            HStack {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) {
                        if !enabled { value = nil; text = "" }
                        else if value == nil { value = 6; text = "6" }
                    }
                if enabled {
                    TextField(hint, text: $text)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: text) { value = Int(text) }
                }
            }
        }
        .onAppear {
            enabled = value != nil
            text = value.map(String.init) ?? ""
        }
    }
}

struct OptionalDoubleField: View {
    let label: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        LabeledContent(label) {
            TextField("—", text: $text)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { value = Double(text) }
        }
        .onAppear { text = value.map { String(format: "%.0f", $0) } ?? "" }
    }
}

struct OptionalRangeField: View {
    let label: String
    @Binding var range: ClosedRange<Int>?
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        LabeledContent(label) {
            HStack {
                TextField("—", text: $minText).frame(width: 40).multilineTextAlignment(.trailing)
                Text("–")
                TextField("—", text: $maxText).frame(width: 40)
                    .onChange(of: maxText) { updateRange() }
                    .onChange(of: minText) { updateRange() }
            }
        }
        .onAppear {
            minText = range.map { String($0.lowerBound) } ?? ""
            maxText = range.map { String($0.upperBound) } ?? ""
        }
    }

    func updateRange() {
        if let lo = Int(minText), let hi = Int(maxText), lo <= hi {
            range = lo...hi
        }
    }
}

struct TagListField: View {
    let label: String
    @Binding var tags: [String]
    let accentColor: Color
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.caption)
                        Button { tags.removeAll { $0 == tag } } label: {
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.15))
                    .foregroundStyle(accentColor)
                    .clipShape(Capsule())
                }
                HStack(spacing: 4) {
                    TextField("Add…", text: $newTag)
                        .frame(width: 80)
                        .font(.caption)
                        .onSubmit {
                            let t = newTag.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty && !tags.contains(t) { tags.append(t) }
                            newTag = ""
                        }
                    if !newTag.isEmpty {
                        Text("↵ Return to add")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

struct AddSeedView: View {
    @Environment(\.dismiss) var dismiss
    var onAdd: (Seed) -> Void
    @State private var seed = Seed(name: "")
    @FocusState private var focusedField: Field?

    enum Field { case name, variety, supplier, url }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            Text("Add Seed")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 14) {
                Group {
LabeledContent("Plant name") {
                        TextField("Required", text: $seed.name)
                            .focused($focusedField, equals: .name)
                    }
                    LabeledContent("Variety") {
                        TextField("Optional", text: $seed.variety)
                            .focused($focusedField, equals: .variety)
                    }
                    LabeledContent("Supplier") {
                        TextField("Optional", text: $seed.supplier)
                            .focused($focusedField, equals: .supplier)
                    }
                    LabeledContent("Website") {
                        HStack(spacing: 6) {
                            TextField("https://", text: $seed.url)
                                .focused($focusedField, equals: .url)
                            Button {
                                let query = [seed.name, seed.variety, seed.supplier]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " ")
                                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let url = URL(string: "https://www.google.com/search?q=\(encoded)+seeds") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .help("Search Google for this seed")
                            .disabled(seed.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                Divider()
                Text("Add sowing windows after saving, in the seed detail view.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    onAdd(seed)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(seed.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 500, height: 310)
        .onAppear {
            // Sheet windows need explicit activation to accept keyboard input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                focusedField = .name
            }
        }
    }
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
