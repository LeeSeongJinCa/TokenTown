import XCTest
import SwiftUI
@testable import TokenTown

final class CityModelTests: XCTestCase {
    let day = "2026-10-08"
    func testBaselineDoesNotRewardHistoryAndFractionalProgressSurvivesRefresh() throws {
        var city = CityState()
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 1_000_000], today: day)
        XCTAssertEqual(city.balance, 200)
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 1_009_999], today: day)
        XCTAssertEqual(city.balance, 200)
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 1_010_001], today: day)
        XCTAssertEqual(city.balance, 201)
        XCTAssertEqual(city.days[day]?.eligibleTokens, 10_001)
        try city.validate()
    }
    func testRepeatedAndReducedTotalsCannotMintCoins() throws {
        var city = CityState()
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 10_000], today: day)
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 40_000], today: day)
        for total in [40_000, 20_000, 0, 40_000] {
            try city.reconcile(sourceID: "codex", dailyTokens: [day: total], today: day)
            XCTAssertEqual(city.balance, 203)
        }
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 50_000], today: day)
        XCTAssertEqual(city.balance, 204)
    }
    func testTwoProvidersShareFractionalProgressAndDailyCap() throws {
        var city = CityState()
        for source in ["codex", "claude_code"] { try city.reconcile(sourceID: source, dailyTokens: [day: 0], today: day) }
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 6_000], today: day)
        try city.reconcile(sourceID: "claude_code", dailyTokens: [day: 4_000], today: day)
        XCTAssertEqual(city.balance, 201)
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 50_000_000], today: day)
        try city.reconcile(sourceID: "claude_code", dailyTokens: [day: 50_000_000], today: day)
        XCTAssertEqual(city.balance, 1200)
        XCTAssertEqual(city.lifetimeEarned, 1000)
        try city.validate()
    }
    func testOfflineCatchupCrossesMonthAndMidnightWithoutRewardingPreBaselineHistory() throws {
        var city = CityState()
        try city.reconcile(sourceID: "codex", dailyTokens: ["2026-09-30": 100_000], today: "2026-09-30")
        let counts = ["2026-09-29": 10_000_000, "2026-09-30": 150_000, "2026-10-01": 70_000, "2026-10-08": 30_000, "2026-10-09": 999_999]
        try city.reconcile(sourceID: "codex", dailyTokens: counts, today: day)
        XCTAssertEqual(city.balance, 215)
        try city.reconcile(sourceID: "codex", dailyTokens: counts, today: day)
        XCTAssertEqual(city.balance, 215)
        XCTAssertNil(city.days["2026-09-29"])
        XCTAssertNil(city.days["2026-10-09"])
    }
    func testLateProviderGetsItsOwnBaselineWithoutErasingAlreadyEarnedCoins() throws {
        var city = CityState()
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 0], today: day)
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 20_000], today: day)
        try city.reconcile(sourceID: "claude_code", dailyTokens: [day: 50_000_000], today: day)
        XCTAssertEqual(city.balance, 202)
        try city.reconcile(sourceID: "claude_code", dailyTokens: [day: 50_010_000], today: day)
        XCTAssertEqual(city.balance, 203)
    }
    func testPurchaseAndFreeMoveValidateFundsOccupancyAndBounds() throws {
        var city = CityState()
        let a = CityPlot(row: 1, column: 1)
        let b = CityPlot(row: 2, column: 3)
        try city.purchase(kindID: "cottage", at: a)
        XCTAssertEqual(city.balance, 80)
        let id = try XCTUnwrap(city.buildings.first?.id)
        XCTAssertThrowsError(try city.purchase(kindID: "cottage", at: a))
        XCTAssertThrowsError(try city.purchase(kindID: "cottage", at: b))
        XCTAssertThrowsError(try city.purchase(kindID: "unknown", at: b))
        XCTAssertThrowsError(try city.move(buildingID: id, to: .init(row: 5, column: 0)))
        try city.move(buildingID: id, to: b)
        XCTAssertEqual(city.buildings.first?.plot, b)
        XCTAssertEqual(city.balance, 80)
        try city.validate()
    }
    func testOccupiedDestinationCannotOverwriteBuildings() throws {
        var city = CityState()
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 0], today: day)
        try city.reconcile(sourceID: "codex", dailyTokens: [day: 10_000_000], today: day)
        try city.purchase(kindID: "cottage", at: .init(row: 0, column: 0))
        try city.purchase(kindID: "cafe", at: .init(row: 0, column: 1))
        let before = city
        XCTAssertThrowsError(try city.move(buildingID: city.buildings[0].id, to: city.buildings[1].plot))
        XCTAssertEqual(city, before)
    }
    func testInvalidUsageAndSaveVersionAreRejected() throws {
        var city = CityState()
        XCTAssertThrowsError(try city.reconcile(sourceID: "codex", dailyTokens: [day: -1], today: day))
        XCTAssertThrowsError(try city.reconcile(sourceID: "codex", dailyTokens: ["2026-02-30": 1], today: day))
        city.lifetimeEarned = Int.max
        XCTAssertThrowsError(try city.validate())
        city.lifetimeEarned = 0
        city.version = 2
        XCTAssertThrowsError(try city.validate())
        city.version = 1
        city.balance = 999
        XCTAssertThrowsError(try city.validate())
    }
}

@MainActor
final class CityPersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TokenTownTests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    func testRestartPreservesPurchaseMoveBalanceAndRewardWatermark() throws {
        let disk = CityDiskPersistence(directory: try directory())
        let city = CityStore(persistence: disk)
        city.reconcile(sourceID: "codex", dailyTokens: ["2026-10-08": 100_000], today: "2026-10-08")
        city.reconcile(sourceID: "codex", dailyTokens: ["2026-10-08": 200_000], today: "2026-10-08")
        XCTAssertTrue(city.purchase(kindID: "cottage", at: .init(row: 0, column: 0)))
        let id = try XCTUnwrap(city.state.buildings.first?.id)
        XCTAssertTrue(city.move(buildingID: id, to: .init(row: 3, column: 4)))
        let restarted = CityStore(persistence: disk)
        XCTAssertEqual(restarted.state, city.state)
        restarted.reconcile(sourceID: "codex", dailyTokens: ["2026-10-08": 200_000], today: "2026-10-08")
        XCTAssertEqual(restarted.state.balance, 90)
    }
    func testFailedWriteLeavesMoneyBuildingsAndWatermarksUnchanged() throws {
        let disk = FailingCityPersistence()
        let city = CityStore(persistence: disk)
        let before = city.state
        disk.failWrites = true
        XCTAssertFalse(city.purchase(kindID: "cottage", at: .init(row: 0, column: 0)))
        XCTAssertEqual(city.state, before)
        XCTAssertNotNil(city.errorMessage)
        city.reconcile(sourceID: "codex", dailyTokens: ["2026-10-08": 30_000], today: "2026-10-08")
        XCTAssertEqual(city.state, before)
    }
    func testCorruptSaveIsPreservedUntilExplicitBackupRecovery() throws {
        let disk = CityDiskPersistence(directory: try directory())
        let city = CityStore(persistence: disk)
        XCTAssertTrue(city.purchase(kindID: "cottage", at: .init(row: 0, column: 0)))
        let broken = Data("broken json".utf8)
        try broken.write(to: disk.file)
        let reopened = CityStore(persistence: disk)
        XCTAssertTrue(reopened.isReadOnly)
        XCTAssertFalse(reopened.purchase(kindID: "cottage", at: .init(row: 0, column: 1)))
        XCTAssertEqual(try Data(contentsOf: disk.file), broken)
        reopened.recoverBackup()
        XCTAssertFalse(reopened.isReadOnly)
        XCTAssertEqual(reopened.state.balance, 200)
        let files = try FileManager.default.contentsOfDirectory(atPath: disk.directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("city.damaged-") })
        XCTAssertTrue(reopened.purchase(kindID: "cottage", at: .init(row: 2, column: 2)))
    }
    func testFutureVersionCannotBeDowngradedUsingBackup() throws {
        let disk = CityDiskPersistence(directory: try directory())
        let city = CityStore(persistence: disk)
        XCTAssertTrue(city.purchase(kindID: "cottage", at: .init(row: 0, column: 0)))
        var future = city.state
        future.version = 99
        let bytes = try JSONEncoder().encode(future)
        try bytes.write(to: disk.file)
        let reopened = CityStore(persistence: disk)
        XCTAssertTrue(reopened.isReadOnly)
        reopened.recoverBackup()
        XCTAssertTrue(reopened.isReadOnly)
        XCTAssertEqual(try Data(contentsOf: disk.file), bytes)
    }
    func testMissingPrimaryLoadsBackup() throws {
        let disk = CityDiskPersistence(directory: try directory())
        let city = CityStore(persistence: disk)
        XCTAssertTrue(city.purchase(kindID: "cottage", at: .init(row: 0, column: 0)))
        try FileManager.default.removeItem(at: disk.file)
        let reopened = CityStore(persistence: disk)
        XCTAssertFalse(reopened.isReadOnly)
        XCTAssertEqual(reopened.state.balance, 200)
    }
}

private final class FailingCityPersistence: CityPersistence {
    var failWrites = false
    var state: CityState?
    func load() throws -> CityState? { state }
    func save(_ state: CityState) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        self.state = state
    }
}

@MainActor
final class CityUsageIntegrationTests: XCTestCase {
    func testRealClaudeAndCodexJSONLToCoinsPurchaseAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TokenTownLogs-\(UUID())")
        let claudeRoot = root.appendingPathComponent("claude")
        let codexRoot = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let claudeFile = claudeRoot.appendingPathComponent("session.jsonl")
        let codexFile = codexRoot.appendingPathComponent("rollout.jsonl")
        func claude(_ id: String, tokens: Int) -> String {
            "{\"type\":\"assistant\",\"requestId\":\"r-\(id)\",\"timestamp\":\"\(timestamp)\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude\",\"usage\":{\"input_tokens\":\(tokens),\"output_tokens\":0,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}}}\n"
        }
        func codex(_ tokens: Int) -> String {
            "{\"type\":\"event_msg\",\"timestamp\":\"\(timestamp)\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":\(tokens),\"cached_input_tokens\":0,\"output_tokens\":0,\"total_tokens\":\(tokens)}}}}\n"
        }
        try claude("a", tokens: 30_000).write(to: claudeFile, atomically: true, encoding: .utf8)
        try codex(40_000).write(to: codexFile, atomically: true, encoding: .utf8)
        let sources = [
            CityUsageSource(id: "claude_code", name: "Claude", read: { LocalUsageReader.claudeEntries(modifiedSince: $0, root: claudeRoot) }),
            CityUsageSource(id: "codex", name: "Codex", read: { LocalUsageReader.codexEntries(modifiedSince: $0, root: codexRoot) })
        ]
        let disk = CityDiskPersistence(directory: root.appendingPathComponent("state"))
        let city = CityStore(persistence: disk)
        let monitor = CityUsageMonitor(city: city, sources: sources)
        await monitor.refresh(now: now)
        XCTAssertEqual(monitor.todayTokens["claude_code"], 30_000)
        XCTAssertEqual(monitor.todayTokens["codex"], 40_000)
        XCTAssertEqual(city.state.balance, 200, "first scan must not reward pre-install history")
        try (claude("a", tokens: 30_000) + claude("b", tokens: 6_000)).write(to: claudeFile, atomically: true, encoding: .utf8)
        try (codex(40_000) + codex(4_000)).write(to: codexFile, atomically: true, encoding: .utf8)
        await monitor.refresh(now: now)
        XCTAssertEqual(city.state.balance, 201)
        XCTAssertTrue(city.purchase(kindID: "cottage", at: .init(row: 2, column: 2)))
        let reopened = CityStore(persistence: disk)
        let nextMonitor = CityUsageMonitor(city: reopened, sources: sources)
        await nextMonitor.refresh(now: now)
        XCTAssertEqual(reopened.state.balance, 81)
        XCTAssertEqual(reopened.state.buildings.count, 1)
        try reopened.state.validate()
    }
    func testEmptySourceDoesNotEstablishBaseline() async {
        let city = CityStore(persistence: FailingCityPersistence())
        let source = CityUsageSource(id: "absent", name: "Absent", read: { _ in [] })
        let monitor = CityUsageMonitor(city: city, sources: [source])
        await monitor.refresh()
        XCTAssertTrue(city.state.sourceStartDays.isEmpty)
        XCTAssertTrue(monitor.detected.isEmpty)
        XCTAssertEqual(city.state.balance, 200)
    }
    func testNativeCityViewRendersAtExpectedSize() {
        let city = CityStore(persistence: FailingCityPersistence())
        let monitor = CityUsageMonitor(city: city, sources: [])
        let renderer = ImageRenderer(content: CityView(city: city, usage: monitor))
        XCTAssertNotNil(renderer.nsImage)
        XCTAssertEqual(renderer.nsImage?.size, NSSize(width: 1000, height: 880))
        if let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            var unsupportedControlPixels = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if c.redComponent > 0.95 && c.greenComponent > 0.65 && c.blueComponent < 0.05 {
                        unsupportedControlPixels += 1
                    }
                }
            }
            XCTAssertEqual(unsupportedControlPixels, 0, "AppKit-backed controls must not become yellow unsupported-render placeholders")
        }
    }
}
