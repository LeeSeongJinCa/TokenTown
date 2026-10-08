import XCTest
import SwiftUI
@testable import TokenTown

final class CityGrowthTests: XCTestCase {
    private func fundedCity() throws -> CityState {
        var city = CityState()
        try city.reconcile(sourceID: "test", dailyTokens: ["2026-10-08": 0], today: "2026-10-08")
        try city.reconcile(sourceID: "test", dailyTokens: ["2026-10-08": 10_000_000], today: "2026-10-08")
        return city
    }
    private func legacyData(_ city: CityState) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(city)) as? [String: Any])
        json["version"] = 1
        json.removeValue(forKey: "districts")
        json.removeValue(forKey: "goalRewards")
        json["buildings"] = try city.buildings.map { building -> [String: Any] in
            var entry = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(building)) as? [String: Any])
            for key in ["paidCoins", "level", "upgradeCoins", "decorated", "decorationCoins"] { entry.removeValue(forKey: key) }
            entry["plot"] = ["row": building.plot.row, "column": building.plot.column]
            return entry
        }
        return try JSONSerialization.data(withJSONObject: json)
    }
    func testV1MigrationPreservesAllPurchasesMoneyAndWatermarks() throws {
        var old = try fundedCity()
        try old.purchase(kindID: "cottage", at: .init(row: 1, column: 1))
        try old.purchase(kindID: "cafe", at: .init(row: 1, column: 2))
        let migrated = try JSONDecoder().decode(CityState.self, from: legacyData(old))
        XCTAssertEqual(migrated, old)
        XCTAssertEqual(migrated.buildings.map(\.paidCoins), [120, 240])
        XCTAssertFalse(migrated.goalCompleted, "Migration must not silently award or spend money")
        XCTAssertEqual(try JSONDecoder().decode(CityState.self, from: JSONEncoder().encode(migrated)), migrated)
    }
    func testHistoricalPricesAreIndependentOfTodaysCatalog() throws {
        var city = CityState()
        let kind = try XCTUnwrap(CityBuildingKind.find("cottage"))
        city.buildings = [.init(id: UUID(), kindID: kind.id, plot: .init(row: 0, column: 0), purchasedAt: Date(), paidCoins: 75)]
        city.balance = 125
        try city.validate()
        XCTAssertNotEqual(city.buildings[0].paidCoins, kind.price)
        XCTAssertEqual(try JSONDecoder().decode(CityState.self, from: JSONEncoder().encode(city)), city)
    }
    func testNeighborGoalRequiresAnEdgeAndIsAwardedOnlyOnce() throws {
        var city = try fundedCity()
        XCTAssertThrowsError(try city.expand(to: .woodland))
        try city.purchase(kindID: "cottage", at: .init(row: 1, column: 1))
        try city.purchase(kindID: "cafe", at: .init(row: 2, column: 2))
        XCTAssertTrue(city.neighborPairs.isEmpty)
        XCTAssertThrowsError(try city.claimNeighborGoal())
        try city.move(buildingID: city.buildings[1].id, to: .init(row: 1, column: 2))
        XCTAssertEqual(city.neighborPairs.count, 1)
        let workCoins = city.lifetimeEarned
        let before = city.balance
        try city.claimNeighborGoal()
        XCTAssertEqual(city.balance, before + CityState.neighborReward)
        XCTAssertEqual(city.lifetimeEarned, workCoins)
        XCTAssertEqual(city.goalEarned, 200)
        XCTAssertThrowsError(try city.claimNeighborGoal())
        try city.expand(to: .riverside)
        XCTAssertEqual(city.capacity, 50)
        XCTAssertThrowsError(try city.expand(to: .woodland))
        try city.move(buildingID: city.buildings[1].id, to: .init(row: 1, column: 2, districtID: 1))
        XCTAssertTrue(city.neighborPairs.isEmpty, "Buildings in different districts cannot be neighbors")
        XCTAssertTrue(city.goalCompleted)
        try city.validate()
    }
    func testUpgradeDecorationAndDistrictPurchasesSurviveRestart() throws {
        var city = try fundedCity()
        try city.purchase(kindID: "cottage", at: .init(row: 0, column: 0))
        try city.purchase(kindID: "cafe", at: .init(row: 0, column: 1))
        try city.claimNeighborGoal()
        try city.expand(to: .woodland)
        let id = city.buildings[0].id
        try city.upgrade(buildingID: id)
        try city.upgrade(buildingID: id)
        XCTAssertThrowsError(try city.upgrade(buildingID: id))
        try city.decorate(buildingID: id)
        XCTAssertThrowsError(try city.decorate(buildingID: id))
        try city.purchase(kindID: "cottage", at: .init(row: 0, column: 0, districtID: 1))
        XCTAssertEqual(city.buildings[0].level, 3)
        XCTAssertEqual(city.buildings[0].upgradeCoins, 360)
        XCTAssertEqual(city.buildings[0].decorationCoins, 50)
        try city.validate()
        let restarted = try JSONDecoder().decode(CityState.self, from: JSONEncoder().encode(city))
        XCTAssertEqual(restarted, city)
        XCTAssertThrowsError(try city.purchase(kindID: "cottage", at: .init(row: 0, column: 0, districtID: 2)))
    }
    func testInvalidAndIncompleteSavesAreRejectedWithoutArithmeticOverflow() throws {
        var city = try fundedCity()
        try city.purchase(kindID: "cottage", at: .init(row: 0, column: 0))
        city.buildings[0].paidCoins = Int.max
        XCTAssertThrowsError(try city.validate())
        XCTAssertThrowsError(try JSONDecoder().decode(CityState.self, from: JSONEncoder().encode(city)))
        XCTAssertThrowsError(try JSONDecoder().decode(CityState.self, from: Data("{\"version\":99}".utf8)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CityState())) as? [String: Any])
        json.removeValue(forKey: "goalRewards")
        XCTAssertThrowsError(try JSONDecoder().decode(CityState.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    @MainActor
    func testDiskMigrationRetainsOriginalAsBackupOnFirstTransaction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GrowthMigration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = CityDiskPersistence(directory: root)
        var old = try fundedCity()
        try old.purchase(kindID: "cottage", at: .init(row: 1, column: 1))
        let original = try legacyData(old)
        try original.write(to: disk.file)
        let store = CityStore(persistence: disk)
        XCTAssertFalse(store.isReadOnly)
        XCTAssertEqual(try Data(contentsOf: disk.file), original)
        XCTAssertTrue(store.decorate(buildingID: old.buildings[0].id))
        XCTAssertEqual(try Data(contentsOf: disk.backup), original)
        XCTAssertEqual(CityStore(persistence: disk).state, store.state)
        var corrupted = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        corrupted["balance"] = 999999
        let bytes = try JSONSerialization.data(withJSONObject: corrupted)
        try bytes.write(to: disk.file)
        XCTAssertTrue(CityStore(persistence: disk).isReadOnly)
        XCTAssertEqual(try Data(contentsOf: disk.file), bytes)
    }
    @MainActor
    func testFailedGrowthTransactionsNeverChangeTheVisibleCity() throws {
        var state = try fundedCity()
        try state.purchase(kindID: "cottage", at: .init(row: 0, column: 0))
        try state.purchase(kindID: "cafe", at: .init(row: 0, column: 1))
        let persistence = GrowthFailingPersistence(state: state)
        let store = CityStore(persistence: persistence)
        XCTAssertFalse(store.claimNeighborGoal())
        XCTAssertFalse(store.upgrade(buildingID: state.buildings[0].id))
        XCTAssertFalse(store.decorate(buildingID: state.buildings[0].id))
        XCTAssertEqual(store.state, state)
        try state.claimNeighborGoal()
        let completed = CityStore(persistence: GrowthFailingPersistence(state: state))
        XCTAssertFalse(completed.expand(to: .woodland))
        XCTAssertEqual(completed.state, state)
    }
    func testUnaffordableGrowthLeavesTheBuildingAndBalanceUnchanged() throws {
        var city = CityState()
        try city.purchase(kindID: "cottage", at: .init(row: 0, column: 0))
        let original = city
        XCTAssertThrowsError(try city.upgrade(buildingID: city.buildings[0].id))
        XCTAssertEqual(city, original)
        try city.decorate(buildingID: city.buildings[0].id)
        XCTAssertEqual(city.balance, 30)
        let decorated = city
        XCTAssertThrowsError(try city.upgrade(buildingID: city.buildings[0].id))
        XCTAssertThrowsError(try city.decorate(buildingID: city.buildings[0].id))
        XCTAssertEqual(city, decorated)
        try city.validate()
    }
    @MainActor
    func testSelectionOutlineCannotCutAcrossBuildingWalls() throws {
        let plot = CityPlot(row: 2, column: 2)
        let building = CityBuilding(id: UUID(), kindID: "cottage", plot: plot, purchasedAt: Date())
        let center = CityMapView.point(plot)
        func wallPixel(selected: UUID?) throws -> NSColor {
            let renderer = ImageRenderer(content: CityMapView(buildings: [building], selected: selected, canPlace: false, onSelect: { _ in }))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            return try XCTUnwrap(bitmap.colorAt(x: Int(center.x) - 20, y: Int(center.y) - 13)?.usingColorSpace(.deviceRGB))
        }
        let normal = try wallPixel(selected: nil)
        let selected = try wallPixel(selected: building.id)
        XCTAssertEqual(selected.redComponent, normal.redComponent, accuracy: 0.01)
        XCTAssertEqual(selected.greenComponent, normal.greenComponent, accuracy: 0.01)
        XCTAssertEqual(selected.blueComponent, normal.blueComponent, accuracy: 0.01)
    }
    @MainActor
    func testEveryDistrictAndLightingModeRenderWithGrowthAndResidents() throws {
        var city = try fundedCity()
        try city.purchase(kindID: "cottage", at: .init(row: 1, column: 1))
        try city.purchase(kindID: "cafe", at: .init(row: 1, column: 2))
        try city.claimNeighborGoal()
        try city.upgrade(buildingID: city.buildings[0].id)
        try city.decorate(buildingID: city.buildings[1].id)
        for district in CityDistrict.allCases {
            for night in [false, true] {
                let renderer = ImageRenderer(content: CityMapView(buildings: city.buildings, selected: nil, canPlace: false, onSelect: { _ in },
                                                                  district: district, neighborPairs: city.neighborPairs, night: night))
                XCTAssertEqual(try XCTUnwrap(renderer.nsImage).size, NSSize(width: CityMapView.width, height: CityMapView.height))
            }
        }
    }
}

private struct GrowthFailingPersistence: CityPersistence {
    let state: CityState
    func load() throws -> CityState? { state }
    func save(_ state: CityState) throws { throw CocoaError(.fileWriteNoPermission) }
}
