import Foundation
import Observation

protocol CityPersistence {
    func load() throws -> CityState?
    func save(_ state: CityState) throws
}

struct CityDiskPersistence: CityPersistence {
    let directory: URL
    var file: URL { directory.appendingPathComponent("city.json") }
    var backup: URL { directory.appendingPathComponent("city.backup.json") }

    func decode(_ url: URL) throws -> CityState {
        let state = try JSONDecoder().decode(CityState.self, from: Data(contentsOf: url))
        try state.validate()
        return state
    }
    func load() throws -> CityState? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else {
            if fm.fileExists(atPath: backup.path) { return try decode(backup) }
            return nil
        }
        do { return try decode(file) }
        catch CityError.unsupportedVersion { throw CityError.unsupportedVersion }
        catch {
            // Do not silently roll back currency or overwrite the evidence of corruption.
            // Recovery is explicit in the UI, and copies the damaged save aside first.
            throw error
        }
    }
    func save(_ state: CityState) throws {
        try state.validate()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        if fm.fileExists(atPath: file.path) {
            _ = try decode(file)
            try Data(contentsOf: file).write(to: backup, options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }
    func recoverBackup() throws -> CityState {
        let state = try decode(backup)
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            // A future schema is never downgraded by the recovery action.
            if let primary = try? JSONDecoder().decode(CityState.self, from: Data(contentsOf: file)),
               primary.version != CityState.schemaVersion { throw CityError.unsupportedVersion }
            try fm.copyItem(at: file, to: directory.appendingPathComponent("city.damaged-\(UUID().uuidString).json"))
        }
        try Data(contentsOf: backup).write(to: file, options: .atomic)
        return state
    }
}

@MainActor @Observable
final class CityStore {
    private(set) var state = CityState()
    private(set) var isReadOnly = false
    var errorMessage: String?
    var notice: String?
    let persistence: any CityPersistence

    init(persistence: any CityPersistence) {
        self.persistence = persistence
        do {
            if let saved = try persistence.load() { state = saved }
            else { try persistence.save(state) }
        } catch {
            isReadOnly = true
            errorMessage = "도시를 열지 못했습니다: \(error.localizedDescription)"
        }
    }
    @discardableResult
    func transact(_ mutation: (inout CityState) throws -> Void) -> Bool {
        do {
            guard !isReadOnly else { throw CityError.readOnly }
            var next = state
            try mutation(&next)
            guard next != state else { return true }
            try persistence.save(next) // Commit to disk before exposing any balance or building change.
            state = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    func reconcile(sourceID: String, dailyTokens: [String: Int], today: String) {
        let oldEarned = state.lifetimeEarned
        if transact({ try $0.reconcile(sourceID: sourceID, dailyTokens: dailyTokens, today: today) }),
           state.lifetimeEarned > oldEarned {
            notice = "+\(state.lifetimeEarned - oldEarned) 코인 · 작업이 도시의 자금이 됐어요."
        }
    }
    func purchase(kindID: String, at plot: CityPlot) -> Bool {
        let result = transact { try $0.purchase(kindID: kindID, at: plot) }
        if result { notice = "\(CityBuildingKind.find(kindID)?.name ?? "건물")이 동네에 들어왔어요." }
        return result
    }
    func move(buildingID: UUID, to plot: CityPlot) -> Bool {
        let result = transact { try $0.move(buildingID: buildingID, to: plot) }
        if result { notice = "건물의 새 주소를 저장했어요." }
        return result
    }
    func recoverBackup() {
        do {
            guard let disk = persistence as? CityDiskPersistence else { throw CityError.readOnly }
            state = try disk.recoverBackup()
            isReadOnly = false
            errorMessage = nil
            notice = "이전 저장본을 복구했습니다. 최근 거래 일부가 되돌아갈 수 있어요."
        } catch { errorMessage = error.localizedDescription }
    }
}
