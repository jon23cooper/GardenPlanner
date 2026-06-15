import Foundation

struct PlantingRecord: Identifiable, Codable, Hashable, Equatable {
    var id: UUID = UUID()
    var seedId: UUID
    var dateSown: Date
    var location: PlantLocation = .custom("Outdoors")
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

// MARK: - PlantLocation

enum PlantLocation: Hashable, Equatable {
    case bed(UUID)
    case custom(String)

    var displayName: String {
        switch self {
        case .bed: return "" // resolved by caller with bed name
        case .custom(let s): return s
        }
    }
}

extension PlantLocation: Codable {
    enum CodingKeys: String, CodingKey { case type, id, name }

    init(from decoder: Decoder) throws {
        // New format: keyed container with "type"
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let type_ = try? c.decode(String.self, forKey: .type) {
            if type_ == "bed", let id = try? c.decode(UUID.self, forKey: .id) {
                self = .bed(id)
                return
            }
            let name = (try? c.decode(String.self, forKey: .name)) ?? type_
            self = .custom(name)
            return
        }
        // Legacy format: plain string (old SowLocation rawValue)
        let s = try decoder.singleValueContainer().decode(String.self)
        self = .custom(s)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bed(let id):
            try c.encode("bed", forKey: .type)
            try c.encode(id, forKey: .id)
        case .custom(let name):
            try c.encode("custom", forKey: .type)
            try c.encode(name, forKey: .name)
        }
    }
}

// MARK: - Other enums

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
