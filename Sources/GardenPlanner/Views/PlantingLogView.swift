import SwiftUI

struct PlantingLogView: View {
    @Environment(AppData.self) private var appData
    @State private var selectedRecord: PlantingRecord?
    @State private var showingAddSheet = false
    @State private var filterYear: Int = Calendar.current.component(.year, from: Date())
    @State private var nameColumnWidth: CGFloat = 160
    @State private var searchText: String = ""

    var years: [Int] {
        let recordYears = Set(appData.plantingRecords.map { $0.year })
        let current = Calendar.current.component(.year, from: Date())
        return Array(recordYears.union([current])).sorted(by: >)
    }

    var filteredRecords: [PlantingRecord] {
        appData.plantingRecords.filter { $0.year == filterYear }
    }

    struct SeedTimeline: Identifiable {
        let seed: Seed
        let records: [PlantingRecord]
        var id: UUID { seed.id }
    }

    var seedTimelines: [SeedTimeline] {
        let grouped = Dictionary(grouping: filteredRecords) { $0.seedId }
        return grouped.compactMap { seedId, records -> SeedTimeline? in
            guard let seed = appData.seed(id: seedId) else { return nil }
            return SeedTimeline(seed: seed, records: records.sorted { $0.dateSown < $1.dateSown })
        }
        .filter { st in
            searchText.isEmpty || st.seed.displayName.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.seed.displayName < $1.seed.displayName }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Year filter
            Picker("Year", selection: $filterYear) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .frame(maxWidth: 400)

            Divider()

            if filteredRecords.isEmpty {
                ContentUnavailableView("No Records", systemImage: "list.clipboard", description: Text("No planting records for \(String(filterYear))."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if seedTimelines.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            PlantingTimelineGrid(
                                seedTimelines: seedTimelines,
                                year: filterYear,
                                nameColumnWidth: $nameColumnWidth,
                                availableWidth: geo.size.width,
                                selectedRecord: $selectedRecord
                            )
                            .padding(16)
                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Planting Log")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter by seed name")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Label("Log Planting", systemImage: "plus")
                }
                .disabled(appData.seeds.isEmpty)
            }
        }
        .inspector(isPresented: .constant(selectedRecord != nil)) {
            if let record = selectedRecord,
               let idx = appData.plantingRecords.firstIndex(where: { $0.id == record.id }) {
                @Bindable var bindableData = appData
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { selectedRecord = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding([.top, .trailing], 8)
                    PlantingRecordDetailView(record: $bindableData.plantingRecords[idx])
                    Divider()
                    HStack {
                        Spacer()
                        Button("Delete Record", role: .destructive) {
                            appData.deletePlantingRecord(id: record.id)
                            selectedRecord = nil
                        }
                    }
                    .padding()
                }
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPlantingRecordView { newRecord in
                appData.addPlantingRecord(newRecord)
                filterYear = newRecord.year
                selectedRecord = newRecord
            }
        }
    }
}

// MARK: - Planting timeline grid

struct PlantingTimelineGrid: View {
    let seedTimelines: [PlantingLogView.SeedTimeline]
    let year: Int
    @Binding var nameColumnWidth: CGFloat
    let availableWidth: CGFloat
    @Binding var selectedRecord: PlantingRecord?
    @Environment(AppData.self) private var appData

    private let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    let rowH: CGFloat = 30
    let gridPadding: CGFloat = 32

    var trackWidth: CGFloat {
        max(300, availableWidth - nameColumnWidth - gridPadding)
    }

    func monthStartFraction(_ month: Int) -> CGFloat {
        let cal = Calendar.current
        let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let yearEnd = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let totalDays = cal.dateComponents([.day], from: yearStart, to: yearEnd).day ?? 365
        let daysIn = cal.dateComponents([.day], from: yearStart, to: monthStart).day ?? 0
        return CGFloat(daysIn) / CGFloat(totalDays)
    }

    func xPosition(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let yearEnd = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let totalDays = cal.dateComponents([.day], from: yearStart, to: yearEnd).day ?? 365
        let clamped = min(max(date, yearStart), yearEnd)
        let dayOffset = cal.dateComponents([.day], from: yearStart, to: clamped).day ?? 0
        return CGFloat(dayOffset) / CGFloat(totalDays) * trackWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: name column + month ticks
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Seed")
                        .font(.caption).fontWeight(.semibold)
                        .frame(width: nameColumnWidth - 8, alignment: .leading)
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 3, height: 16)
                        .cornerRadius(1.5)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    nameColumnWidth = max(80, nameColumnWidth + val.translation.width)
                                }
                        )
                        .cursor(.resizeLeftRight)
                        .padding(.trailing, 5)
                }
                .frame(width: nameColumnWidth)

                ZStack(alignment: .topLeading) {
                    ForEach(1...12, id: \.self) { m in
                        Text(months[m - 1])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .offset(x: monthStartFraction(m) * trackWidth + 2)
                    }
                }
                .frame(width: trackWidth, height: 16, alignment: .topLeading)
            }
            .padding(.bottom, 4)

            Divider()

            ForEach(seedTimelines) { st in
                HStack(spacing: 0) {
                    Text(st.seed.displayName)
                        .font(.callout).lineLimit(1)
                        .frame(width: nameColumnWidth, alignment: .leading)

                    ZStack(alignment: .leading) {
                        // Track background with month ticks
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: trackWidth, height: rowH - 10)

                        ForEach(2...12, id: \.self) { m in
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 1, height: rowH - 10)
                                .offset(x: monthStartFraction(m) * trackWidth)
                        }

                        // Sowing markers
                        ForEach(st.records) { record in
                            Circle()
                                .fill(Color(hex: st.seed.colorHex))
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                                .frame(width: 12, height: 12)
                                .shadow(radius: selectedRecord?.id == record.id ? 0 : 1)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.accentColor, lineWidth: selectedRecord?.id == record.id ? 2 : 0)
                                        .frame(width: 16, height: 16)
                                )
                                .offset(x: xPosition(for: record.dateSown) - 6)
                                .help("\(record.dateSown.formatted(date: .abbreviated, time: .omitted)) · \(record.quantitySown) sown")
                                .onTapGesture { selectedRecord = record }
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        appData.deletePlantingRecord(id: record.id)
                                        if selectedRecord?.id == record.id { selectedRecord = nil }
                                    }
                                }
                        }
                    }
                    .frame(width: trackWidth, height: rowH, alignment: .leading)
                }
                .padding(.vertical, 2)

                if st.id != seedTimelines.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
    }
}

struct PlantingRecordDetailView: View {
    @Binding var record: PlantingRecord
    @Environment(AppData.self) private var appData

    var seedName: String {
        appData.seed(id: record.seedId)?.displayName ?? "Unknown Seed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(seedName).font(.title).fontWeight(.bold)

                GroupBox("Sowing") {
                    LabeledContent("Date sown") { DatePicker("", selection: $record.dateSown, displayedComponents: .date).labelsHidden() }
                    LabeledContent("Location") {
                        LocationPicker(selection: $record.location)
                    }
                    LabeledContent("Quantity sown") {
                        Stepper("\(record.quantitySown)", value: $record.quantitySown, in: 1...9999)
                    }
                }

                GroupBox("Progress") {
                    OptionalDateField(label: "Transplanted", date: $record.dateTransplanted)
                    OptionalDateField(label: "First harvest", date: $record.dateFirstHarvest)
                    OptionalDateField(label: "Last harvest", date: $record.dateLastHarvest)
                    LabeledContent("Outcome") {
                        Picker("", selection: $record.outcome) {
                            ForEach(Outcome.allCases, id: \.self) { Text($0.rawValue) }
                        }.labelsHidden()
                    }
                }

                GroupBox("Notes") {
                    TextEditor(text: $record.notes)
                        .frame(minHeight: 80)
                }
            }
            .padding()
        }
    }
}

// MARK: - LocationPicker

struct LocationPicker: View {
    @Binding var selection: PlantLocation
    @Environment(AppData.self) private var appData
    @State private var showingAddSheet = false
    @State private var newLocationName = ""

    var body: some View {
        HStack {
            Picker("", selection: $selection) {
                if !appData.gardenBeds.isEmpty {
                    Section("Garden Beds") {
                        ForEach(appData.gardenBeds) { bed in
                            Text(bed.name).tag(PlantLocation.bed(bed.id))
                        }
                    }
                }
                Section("Other") {
                    ForEach(appData.customLocations, id: \.self) { loc in
                        Text(loc).tag(PlantLocation.custom(loc))
                    }
                }
            }
            .labelsHidden()

            Button {
                newLocationName = ""
                showingAddSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add custom location")
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCustomLocationView(name: $newLocationName) { name in
                if !appData.customLocations.contains(name) {
                    appData.customLocations.append(name)
                }
                selection = .custom(name)
            }
        }
    }
}

struct AddCustomLocationView: View {
    @Binding var name: String
    var onAdd: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Location")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            VStack(spacing: 16) {
                TextField("e.g. Cold frame, Polytunnel", text: $name)
                    .focused($focused)
                    .onSubmit { commit() }

                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Add") { commit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 300)
        .onAppear { focused = true }
    }

    func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        dismiss()
    }
}

// MARK: - OptionalDateField

struct OptionalDateField: View {
    let label: String
    @Binding var date: Date?
    @State private var enabled = false
    @State private var pickerDate = Date()

    var body: some View {
        LabeledContent(label) {
            HStack {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) {
                        date = enabled ? pickerDate : nil
                    }
                if enabled {
                    DatePicker("", selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0; pickerDate = $0 }
                    ), displayedComponents: .date).labelsHidden()
                }
            }
        }
        .onAppear {
            enabled = date != nil
            pickerDate = date ?? Date()
        }
    }
}

// MARK: - AddPlantingRecordView

struct AddPlantingRecordView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) var dismiss
    var onAdd: (PlantingRecord) -> Void

    @State private var selectedSeedId: UUID?
    @State private var dateSown = Date()
    @State private var location: PlantLocation = .custom("Outdoors")
    @State private var quantitySown = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Seed", selection: $selectedSeedId) {
                        Text("Select…").tag(Optional<UUID>.none)
                        ForEach(appData.seeds.sorted { $0.displayName < $1.displayName }) { seed in
                            Text(seed.displayName).tag(Optional(seed.id))
                        }
                    }
                }
                Section {
                    DatePicker("Date sown", selection: $dateSown, displayedComponents: .date)
                    LabeledContent("Location") {
                        LocationPicker(selection: $location)
                    }
                    Stepper("Quantity: \(quantitySown)", value: $quantitySown, in: 1...9999)
                }
            }
            .navigationTitle("Log Planting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let seedId = selectedSeedId else { return }
                        let record = PlantingRecord(seedId: seedId, dateSown: dateSown, location: location, quantitySown: quantitySown)
                        onAdd(record)
                        dismiss()
                    }
                    .disabled(selectedSeedId == nil)
                }
            }
        }
        .frame(width: 420, height: 300)
        .onAppear {
            // Default to first bed if available, otherwise first custom location
            if let firstBed = appData.gardenBeds.first {
                location = .bed(firstBed.id)
            } else if let first = appData.customLocations.first {
                location = .custom(first)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
