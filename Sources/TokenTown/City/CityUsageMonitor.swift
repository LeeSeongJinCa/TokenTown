import Foundation
import Observation

struct CityUsageSource: Sendable {
    let id: String
    let name: String
    let read: @Sendable (Date) async -> [LocalUsageReader.Entry]
    static let local: [Self] = [
        .init(id: "codex", name: "Codex", read: { await LocalUsageCache.shared.codexEntries(modifiedSince: $0) }),
        .init(id: "claude_code", name: "Claude Code", read: { await LocalUsageCache.shared.claudeEntries(modifiedSince: $0) })
    ]
    static func totals(_ entries: [LocalUsageReader.Entry]) -> [String: Int] {
        entries.reduce(into: [:]) { result, entry in
            guard entry.total > 0 else { return }
            result[entry.localDay, default: 0] += entry.total
        }
    }
}

@MainActor @Observable
final class CityUsageMonitor {
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var todayTokens: [String: Int] = [:]
    private(set) var detected: Set<String> = []
    let sources: [CityUsageSource]
    private let city: CityStore
    private var timer: Timer?
    init(city: CityStore, sources: [CityUsageSource] = CityUsageSource.local) {
        self.city = city
        self.sources = sources
    }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 10
        Task { await refresh() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh(now: Date = Date()) async {
        guard !isRefreshing, !city.isReadOnly else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let formatter = LocalUsageReader.localDayFormatter()
        let today = formatter.string(from: now)
        let earliest = city.state.sourceStartDays.values.min().flatMap { formatter.date(from: $0) }
            ?? Calendar.current.startOfDay(for: now)
        await withTaskGroup(of: (String, [String: Int]).self) { group in
            for source in sources {
                group.addTask { (source.id, CityUsageSource.totals(await source.read(earliest))) }
            }
            for await (id, totals) in group {
                todayTokens[id] = totals[today, default: 0]
                // Empty scans might mean missing/deleted logs or a permissions failure.
                // Never establish a zero baseline until an actual usage record exists.
                guard !totals.isEmpty else { detected.remove(id); continue }
                detected.insert(id)
                city.reconcile(sourceID: id, dailyTokens: totals, today: today)
            }
        }
        lastUpdated = now
    }
}
