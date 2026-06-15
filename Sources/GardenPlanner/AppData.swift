import Foundation
import SwiftUI

@Observable
final class AppData {
    var seeds: [Seed] = [] { didSet { save() } }
    var plantingRecords: [PlantingRecord] = [] { didSet { save() } }
    var gardenBeds: [GardenBed] = [] { didSet { save() } }
    var customLocations: [String] = ["Indoors", "Outdoors", "Greenhouse"] { didSet { save() } }

    var webServerEnabled: Bool = true { didSet { save(); webServerEnabled ? startWebServer() : stopWebServer() } }
    var webServerPort: Int = 8080 { didSet { save(); if webServerEnabled { restartWebServer() } } }
    var webServerRunning: Bool = false
    var webServerError: String? = nil

    private var _webServer: WebServer?

    // Frost dates stored as month+day only (year is ignored)
    var lastFrostMonth: Int = 4 { didSet { save() } }
    var lastFrostDay: Int = 15 { didSet { save() } }
    var firstFrostMonth: Int = 10 { didSet { save() } }
    var firstFrostDay: Int = 15 { didSet { save() } }

    private let dataDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dataDir = docs.appendingPathComponent("GardenPlanner/Data")
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        load()
        if webServerEnabled { startWebServer() }
    }

    // MARK: - Web server lifecycle

    func startWebServer() {
        _webServer?.stop()
        webServerError = nil
        let server = WebServer(port: UInt16(clamping: webServerPort), appData: self)
        server.onStateChange = { [weak self] running in self?.webServerRunning = running }
        server.onError = { [weak self] msg in self?.webServerError = msg }
        server.start()
        _webServer = server
    }

    func stopWebServer() {
        _webServer?.stop()
        _webServer = nil
        webServerRunning = false
    }

    func restartWebServer() {
        stopWebServer()
        startWebServer()
    }

    // MARK: - Frost date helpers

    func lastFrostDate(year: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: lastFrostMonth, day: lastFrostDay))!
    }

    func firstFrostDate(year: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: firstFrostMonth, day: firstFrostDay))!
    }

    func resolve(_ spec: SowDateSpec, year: Int) -> Date {
        switch spec.kind {
        case .fixed:
            return Calendar.current.date(from: DateComponents(year: year, month: spec.month, day: spec.day))!
        case .frostRelative:
            let frost = lastFrostDate(year: year)
            return Calendar.current.date(byAdding: .weekOfYear, value: spec.weeksFromFrost, to: frost)!
        }
    }

    func resolvedWindows(for seed: Seed, year: Int) -> [(window: SowingWindow, start: Date, end: Date)] {
        seed.sowingWindows.map { w in
            (w, resolve(w.start, year: year), resolve(w.end, year: year))
        }
    }

    // MARK: - Lookup helpers

    func seed(id: UUID) -> Seed? {
        seeds.first { $0.id == id }
    }

    func plantingRecords(for seedId: UUID) -> [PlantingRecord] {
        plantingRecords.filter { $0.seedId == seedId }
    }

    // MARK: - Mutations

    func addSeed(_ seed: Seed) {
        seeds.append(seed)
        save()
    }

    func updateSeed(_ seed: Seed) {
        if let i = seeds.firstIndex(where: { $0.id == seed.id }) {
            seeds[i] = seed
            save()
        }
    }

    func deleteSeed(id: UUID) {
        seeds.removeAll { $0.id == id }
        plantingRecords.removeAll { $0.seedId == id }
        for i in gardenBeds.indices {
            gardenBeds[i].cells.removeAll { $0.seedId == id }
        }
        save()
    }

    func addPlantingRecord(_ record: PlantingRecord) {
        plantingRecords.append(record)
        if let i = seeds.firstIndex(where: { $0.id == record.seedId }) {
            seeds[i].quantityPackets = max(0, seeds[i].quantityPackets - record.quantitySown)
        }
        save()
    }

    func updatePlantingRecord(_ record: PlantingRecord) {
        if let i = plantingRecords.firstIndex(where: { $0.id == record.id }) {
            plantingRecords[i] = record
            save()
        }
    }

    func deletePlantingRecord(id: UUID) {
        plantingRecords.removeAll { $0.id == id }
        save()
    }

    func addBed(_ bed: GardenBed) {
        gardenBeds.append(bed)
        save()
    }

    func updateBed(_ bed: GardenBed) {
        if let i = gardenBeds.firstIndex(where: { $0.id == bed.id }) {
            gardenBeds[i] = bed
            save()
        }
    }

    func deleteBed(id: UUID) {
        gardenBeds.removeAll { $0.id == id }
        save()
    }

    func plantSeed(_ seedId: UUID, in bedId: UUID, at position: GridPosition, year: Int) {
        guard let bedIdx = gardenBeds.firstIndex(where: { $0.id == bedId }) else { return }
        // Remove any existing cell at this position for this year
        gardenBeds[bedIdx].cells.removeAll { $0.row == position.row && $0.column == position.column && $0.year == year }
        let cell = BedCell(row: position.row, column: position.column, year: year, seedId: seedId)
        gardenBeds[bedIdx].cells.append(cell)
        save()
    }

    func clearCell(in bedId: UUID, at position: GridPosition, year: Int) {
        guard let bedIdx = gardenBeds.firstIndex(where: { $0.id == bedId }) else { return }
        gardenBeds[bedIdx].cells.removeAll { $0.row == position.row && $0.column == position.column && $0.year == year }
        save()
    }

    // MARK: - Persistence

    private struct AppDataFile: Codable {
        var seeds: [Seed]
        var plantingRecords: [PlantingRecord]
        var gardenBeds: [GardenBed]
        var lastFrostMonth: Int
        var lastFrostDay: Int
        var firstFrostMonth: Int
        var firstFrostDay: Int
        var customLocations: [String]?
        var webServerEnabled: Bool?
        var webServerPort: Int?
    }

    func save() {
        let file = AppDataFile(
            seeds: seeds,
            plantingRecords: plantingRecords,
            gardenBeds: gardenBeds,
            lastFrostMonth: lastFrostMonth,
            lastFrostDay: lastFrostDay,
            firstFrostMonth: firstFrostMonth,
            firstFrostDay: firstFrostDay,
            customLocations: customLocations,
            webServerEnabled: webServerEnabled,
            webServerPort: webServerPort
        )
        let url = dataDir.appendingPathComponent("garden.json")
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url)
        }
    }

    func load() {
        let url = dataDir.appendingPathComponent("garden.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(AppDataFile.self, from: data) else { return }
        seeds = file.seeds
        plantingRecords = file.plantingRecords
        gardenBeds = file.gardenBeds
        lastFrostMonth = file.lastFrostMonth
        lastFrostDay = file.lastFrostDay
        firstFrostMonth = file.firstFrostMonth
        firstFrostDay = file.firstFrostDay
        customLocations = file.customLocations ?? ["Indoors", "Outdoors", "Greenhouse"]
        webServerEnabled = file.webServerEnabled ?? true
        webServerPort = file.webServerPort ?? 8080
    }
}
