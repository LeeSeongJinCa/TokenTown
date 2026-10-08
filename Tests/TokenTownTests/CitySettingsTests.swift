import XCTest
import SwiftUI
@testable import TokenTown

final class CitySettingsTests: XCTestCase {
    @MainActor
    func testCityWindowHasFixedSizeAndCannotEnterFullScreen() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        TokenTownDelegate.configureCityWindow(window, availableHeight: 900)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, NSSize(width: 1000, height: 840))
        XCTAssertEqual(window.contentMaxSize, window.contentMinSize)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(TokenTownDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testCityViewFillsAnExpandedWindow() throws {
        let city = CityStore(persistence: ConnectionTestPersistence())
        let usage = CityUsageMonitor(city: city, sources: [])
        let renderer = ImageRenderer(content: CityView(city: city, usage: usage).frame(width: 1400, height: 1000))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 1400)
        XCTAssertEqual(image.size.height, 1000)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let corner = try XCTUnwrap(bitmap.colorAt(x: 1399, y: 999))
        XCTAssertEqual(corner.alphaComponent, 1, accuracy: 0.01)
    }

    func testConnectionSettingsAreValidatedBeforeEitherProviderIsSaved() throws {
        let suite = "TokenTownConnections-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try CityConnections.save(codex: root.path, claude: "", defaults: defaults)
        XCTAssertEqual(CustomScanRoots.storedValue(for: "codex", defaults: defaults), root.path)
        XCTAssertThrowsError(try CityConnections.save(codex: "", claude: root.appendingPathComponent("missing").path, defaults: defaults))
        XCTAssertEqual(CustomScanRoots.storedValue(for: "codex", defaults: defaults), root.path)
        XCTAssertThrowsError(try CityConnections.save(codex: "/", claude: "", defaults: defaults))
        try CityConnections.save(codex: "", claude: "", defaults: defaults)
        XCTAssertNil(CustomScanRoots.storedValue(for: "codex", defaults: defaults))
    }

    @MainActor
    func testConnectionStatusClearsWhenPreviouslyDetectedLogsDisappear() async {
        let feed = ConnectionUsageSequence()
        let city = CityStore(persistence: ConnectionTestPersistence())
        let source = CityUsageSource(id: "codex", name: "Codex", read: { _ in await feed.read() })
        let usage = CityUsageMonitor(city: city, sources: [source])
        await usage.refresh()
        XCTAssertTrue(usage.detected.contains("codex"))
        let original = city.state
        await usage.refresh()
        XCTAssertFalse(usage.detected.contains("codex"))
        XCTAssertEqual(city.state, original)
    }

    @MainActor
    func testEveryBuildingFootprintReachesTheFrontHalfOfItsGroundTile() throws {
        let plot = CityPlot(row: 2, column: 2)
        let center = CityMapView.point(plot)
        for kind in CityBuildingKind.catalog {
            let building = CityBuilding(id: UUID(), kindID: kind.id, plot: plot, purchasedAt: Date())
            let renderer = ImageRenderer(content: CityMapView(buildings: [building], selected: nil, canPlace: false, onSelect: { _ in }))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let pixel = try XCTUnwrap(bitmap.colorAt(x: Int(center.x - 5), y: Int(center.y + 5))?.usingColorSpace(.deviceRGB))
            let swatch = ImageRenderer(content: Rectangle().fill(TownPalette.building(kind.color)).frame(width: 20, height: 20))
            swatch.scale = 1
            let swatchImage = try XCTUnwrap(swatch.nsImage)
            let swatchBitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(swatchImage.tiffRepresentation)))
            let expected = try XCTUnwrap(swatchBitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(pixel.redComponent, expected.redComponent, accuracy: 0.04, kind.id)
            XCTAssertEqual(pixel.greenComponent, expected.greenComponent, accuracy: 0.04, kind.id)
            XCTAssertEqual(pixel.blueComponent, expected.blueComponent, accuracy: 0.04, kind.id)
        }
    }
}

private actor ConnectionUsageSequence {
    private var first = true
    func read() -> [LocalUsageReader.Entry] {
        guard first else { return [] }
        first = false
        return [.init(id: "fixture", date: Date(), localDay: LocalUsageReader.todayKey(), model: "fixture",
                      input: 100, output: 0, cacheWrite: 0, cacheRead: 0)]
    }
}

private struct ConnectionTestPersistence: CityPersistence {
    func load() throws -> CityState? { nil }
    func save(_ state: CityState) throws {}
}
