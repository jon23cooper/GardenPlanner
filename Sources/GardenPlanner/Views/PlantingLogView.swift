import SwiftUI

struct PlantingLogView: View {
    @Environment(AppData.self) private var appData
    @State private var selectedRecord: PlantingRecord?
    @State private var showingAddSheet = false
    @State private var filterYear: Int = Calendar.current.component(.year, from: Date())

    var years: [Int] {
        let recordYears = Set(appData.plantingRecords.map { $0.year })
        let current = Calendar.current.component(.year, from: Date())
        return Array(recordYears.union([current])).sorted(by: >)
    }

    var filteredRecords: [PlantingRecord] {
        appData.plantingRecords
            .filter { $0.year == filterYear }
            .sorted { $0.dateSown > $1.dateSown }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Year filter
                Picker("Year", selection: $filterYear) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(8)

                if filteredRecords.isEmpty {
                    ContentUnavailableView("No Records", systemImage: "list.clipboard", description: Text("No planting records for \(String(filterYear))."))
                } else {
                    List(filteredRecords, selection: $selectedRecord) { record in
                        PlantingRecordRow(record: record)
                            .tag(record)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    appData.deletePlantingRecord(id: record.id)
                                    if selectedRecord?.id == record.id { selectedRecord = nil }
                                }
                            }
                    }
                }
            }
            .navigationTitle("Planting Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddSheet = true } label: {
                        Label("Log Planting", systemImage: "plus")
                    }
                    .disabled(appData.seeds.isEmpty)
                }
            }
        } detail: {
            if let record = selectedRecord,
               let idx = appData.plantingRecords.firstIndex(where: { $0.id == record.id }) {
                @Bindable var bindableData = appData
                PlantingRecordDetailView(record: $bindableData.plantingRecords[idx])
            } else {
                ContentUnavailableView("Select a Record", systemImage: "list.clipboard", description: Text("Choose a record to view or edit details."))
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

struct PlantingRecordRow: View {
    @Environment(AppData.self) private var appData
    let record: PlantingRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(appData.seed(id: record.seedId)?.displayName ?? "Unknown Seed")
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(record.dateSown, format: .dateTime.day().month())
                    Text("·")
                    Text(record.location.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            outcomeTag(record.outcome)
        }
    }

    func outcomeTag(_ outcome: Outcome) -> some View {
        let (color, label): (Color, String) = {
            switch outcome {
            case .ongoing: return (.blue, "Ongoing")
            case .success: return (.green, "Success")
            case .partialSuccess: return (.orange, "Partial")
            case .failure: return (.red, "Failed")
            }
        }()
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
                        Picker("", selection: $record.location) {
                            ForEach(SowLocation.allCases, id: \.self) { Text($0.rawValue) }
                        }.labelsHidden()
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
        .onChange(of: record) { appData.save() }
    }
}

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

struct AddPlantingRecordView: View {
    @Environment(AppData.self) private var appData
    @Environment(\.dismiss) var dismiss
    var onAdd: (PlantingRecord) -> Void

    @State private var selectedSeedId: UUID?
    @State private var dateSown = Date()
    @State private var location = SowLocation.indoor
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
                    Picker("Location", selection: $location) {
                        ForEach(SowLocation.allCases, id: \.self) { Text($0.rawValue) }
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
        .frame(width: 380, height: 280)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
