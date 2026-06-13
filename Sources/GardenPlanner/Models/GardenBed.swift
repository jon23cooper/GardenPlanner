import Foundation

struct GardenBed: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var columns: Int
    var rows: Int
    var squareSizeCm: Double = 30
    var notes: String = ""
    var cells: [BedCell] = []

    // Returns the cell at a given position for a given year, or nil
    func cell(at position: GridPosition, year: Int) -> BedCell? {
        cells.first { $0.row == position.row && $0.column == position.column && $0.year == year }
    }
}

struct BedCell: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var row: Int
    var column: Int
    var year: Int
    var seedId: UUID
    var plantingRecordId: UUID?
    var notes: String = ""
}
