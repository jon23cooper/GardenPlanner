import Foundation

struct PlantingRecord: Identifiable, Codable, Hashable, Equatable {
    var id: UUID = UUID()
    var seedId: UUID
    var dateSown: Date
    var location: SowLocation = .indoor
    var bedId: UUID?
    var gridPositions: [GridPosition] = []
    var quantitySown: Int = 1
    var dateTransplanted: Date?
    var dateFirstHarvest: Date?
    var dateLastHarvest: Date?
    var outcome: Outcome = .ongoing
    var notes: String = ""
    var year: Int {
        Calendar.current.component(.year, from: dateSown)
    }
}

enum SowLocation: String, Codable, CaseIterable {
    case indoor = "Indoors"
    case outdoor = "Outdoors"
    case greenhouse = "Greenhouse"
}

enum Outcome: String, Codable, CaseIterable {
    case ongoing = "Ongoing"
    case success = "Success"
    case partialSuccess = "Partial Success"
    case failure = "Failure"
}

struct GridPosition: Codable, Hashable {
    var row: Int
    var column: Int
}
