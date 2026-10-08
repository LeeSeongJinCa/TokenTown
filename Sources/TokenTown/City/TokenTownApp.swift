import AppKit
import Darwin
import SwiftUI

@main
@MainActor
enum TokenTownApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = TokenTownDelegate()
        app.delegate = delegate
        // AppKit owns the window lifecycle; a Settings-only SwiftUI App would
        // automatically create an empty Settings window for this regular app.
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class TokenTownDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var monitor: CityUsageMonitor?
    private var city: CityStore?
    private var lockDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--render-city-preview"), args.count > index + 1 {
            Task {
                do { try await renderPreview(to: URL(fileURLWithPath: args[index + 1])) }
                catch { fputs("Preview failed: \(error)\n", stderr) }
                NSApp.terminate(nil)
            }
            return
        }
        if SingleInstance.shouldYieldToRunningInstance() { NSApp.terminate(nil); return }
        let directory = Self.stateDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            lockDescriptor = Darwin.open(directory.appendingPathComponent("city.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                showFatalError("이 저장 폴더를 사용하는 TokenTown이 이미 실행 중이거나 폴더를 잠글 수 없습니다.")
                return
            }
        } catch { showFatalError(error.localizedDescription); return }
        // Keep upstream parser caches separate from PokeTokenBar's saves and preferences.
        setenv("PTB_STATE_DIR", directory.appendingPathComponent("usage-cache").path, 1)
        signal(SIGPIPE, SIG_IGN)
        let store = CityStore(persistence: CityDiskPersistence(directory: directory))
        let usage = CityUsageMonitor(city: store)
        city = store
        monitor = usage
        let view = CityView(city: store, usage: usage)
        let controller = NSHostingController(rootView: GeometryReader { geometry in
            ScrollView(.vertical) {
                view.frame(minHeight: geometry.size.height, alignment: .topLeading)
            }
            .background(TownPalette.paper)
        })
        let window = NSWindow(contentViewController: controller)
        window.title = "TokenTown"
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 960
        Self.configureCityWindow(window, availableHeight: availableHeight)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        showCity()
        installMenu()
        observeBalance()
        usage.start()
    }
    static func stateDirectory() -> URL {
        AppStatePaths.cityDirectory()
    }

    static func configureCityWindow(_ window: NSWindow, availableHeight: CGFloat) {
        window.styleMask = [.titled, .closable, .miniaturizable]
        let size = NSSize(width: 1000, height: min(880, availableHeight - 60))
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.collectionBehavior = [.fullScreenNone]
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "building.2.fill", accessibilityDescription: "TokenTown")
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        for _ in 0..<3 {
            let summary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            summary.isEnabled = false
            menu.addItem(summary)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "내 도시 열기", action: #selector(showCity), keyEquivalent: "").target = self
        menu.addItem(withTitle: "사용량 새로고침", action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "메뉴 막대에서 계속 실행", action: #selector(runInBackground), keyEquivalent: "q").target = self
        let quitItem = menu.addItem(withTitle: "TokenTown 완전히 종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command, .option]
        quitItem.target = self
        item.menu = menu
        statusItem = item
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "TokenTown", action: nil, keyEquivalent: "")
        appItem.submenu = menu.copy() as? NSMenu
        for _ in 0..<4 { appItem.submenu?.removeItem(at: 0) }
        appItem.submenu?.delegate = nil
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard let city, let monitor else { return }
        let today = city.state.days[LocalUsageReader.todayKey(), default: CityRewardDay()]
        menu.item(at: 0)?.title = "자금 \(city.state.balance.formatted()) 코인 · 건물 \(city.state.buildings.count)개"
        menu.item(at: 1)?.title = "오늘 보상 +\(today.creditedCoins.formatted()) / \(CityState.dailyCoinCap.formatted()) 코인"
        menu.item(at: 2)?.title = monitor.sources.map { source in
            "\(source.name): \(monitor.detected.contains(source.id) ? TokenFormatter.compact(monitor.todayTokens[source.id, default: 0]) : "로그 대기 중")"
        }.joined(separator: " · ")
    }
    private func observeBalance() {
        guard let city else { return }
        statusItem?.button?.title = " \(city.state.balance.formatted())"
        statusItem?.button?.toolTip = "TokenTown · \(city.state.balance.formatted()) 코인"
        withObservationTracking { _ = city.state.balance } onChange: { [weak self] in
            Task { @MainActor in self?.observeBalance() }
        }
    }
    @objc private func showCity() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings() {
        guard let monitor else { return }
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: CitySettingsView(usage: monitor))
            let settings = NSWindow(contentViewController: controller)
            settings.title = "TokenTown 설정"
            settings.styleMask = [.titled, .closable]
            settings.isReleasedWhenClosed = false
            settings.delegate = self
            settings.center()
            settingsWindow = settings
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func refresh() { Task { await monitor?.refresh() } }
    @objc private func runInBackground() {
        window?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let other = closing === window ? settingsWindow : window
        if other?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCity()
        return false // Already handled: do not let SwiftUI reopen its empty Settings scene.
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }
    private func showFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "TokenTown을 열지 못했습니다"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
    private func renderPreview(to url: URL) async throws {
        var sample = CityState()
        let today = LocalUsageReader.todayKey()
        sample.sourceStartDays = ["codex": today, "claude_code": today]
        sample.days[today] = CityRewardDay(highWater: ["codex": 6_800_000, "claude_code": 3_200_000], eligibleTokens: 10_000_000, creditedCoins: 1000)
        sample.lifetimeEarned = 1000
        // A prior day provides enough sample funds for a populated native UI render.
        let yesterday = LocalUsageReader.localDayFormatter().string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        sample.days[yesterday] = CityRewardDay(highWater: ["codex": 10_000_000], eligibleTokens: 10_000_000, creditedCoins: 1000)
        sample.lifetimeEarned += 1000
        sample.balance += sample.lifetimeEarned
        try sample.purchase(kindID: "cottage", at: .init(row: 1, column: 1))
        try sample.purchase(kindID: "cafe", at: .init(row: 1, column: 3))
        try sample.purchase(kindID: "bookshop", at: .init(row: 3, column: 1))
        try sample.purchase(kindID: "apartment", at: .init(row: 2, column: 2))
        let store = CityStore(persistence: CityPreviewPersistence(state: sample))
        let previewSources = CityUsageSource.local.map { source in
            let count = sample.days[today]!.highWater[source.id, default: 0]
            let entry = LocalUsageReader.Entry(id: "preview", date: Date(), localDay: today, model: "preview",
                                              input: count, output: 0, cacheWrite: 0, cacheRead: 0)
            return CityUsageSource(id: source.id, name: source.name, read: { _ in [entry] })
        }
        let usage = CityUsageMonitor(city: store, sources: previewSources)
        await usage.refresh()
        let renderer = ImageRenderer(content: CityView(city: store, usage: usage).frame(width: 1000, height: 880))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CityError.invalidSave
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }
}

private struct CityPreviewPersistence: CityPersistence {
    let state: CityState
    func load() throws -> CityState? { state }
    func save(_ state: CityState) throws {}
}
