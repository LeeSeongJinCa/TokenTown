import AppKit
import SwiftUI

/// Adds log roots without replacing the parser's automatically discovered locations.
enum CityConnections {
    static func validate(_ raw: String, provider: String) throws {
        let defaults = provider == "codex"
            ? LocalUsageReader.codexSessionRoots()
            : LocalUsageReader.computeClaudeProjectRoots(configDirValue: nil)
        for part in raw.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let path = part.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            let expanded = CustomScanRoots.expand(path)
            guard !expanded.isEmpty else { throw ConnectionError.invalidFolder(path) }
            let accepted = CustomScanRoots.union(defaults: defaults, extraRaw: path)
            guard expanded.allSatisfy({ extra in accepted.contains { $0.standardizedFileURL == extra.standardizedFileURL } }) else {
                throw ConnectionError.tooBroad(path)
            }
        }
    }
    static func save(codex: String, claude: String, defaults: UserDefaults = .standard) throws {
        try validate(codex, provider: "codex")
        try validate(claude, provider: "claude_code")
        defaults.set(codex.trimmingCharacters(in: .whitespacesAndNewlines), forKey: CustomScanRoots.defaultsKey(for: "codex"))
        defaults.set(claude.trimmingCharacters(in: .whitespacesAndNewlines), forKey: CustomScanRoots.defaultsKey(for: "claude_code"))
        LocalUsageReader.invalidateProjectRootsCache()
    }
    enum ConnectionError: LocalizedError {
        case invalidFolder(String), tooBroad(String)
        var errorDescription: String? {
            switch self {
            case .invalidFolder(let path): return "읽을 수 있는 로그 폴더가 없습니다: \(path)"
            case .tooBroad(let path): return "기본 로그 경로를 포함하는 상위 폴더 대신 실제 sessions 또는 projects 폴더를 선택하세요: \(path)"
            }
        }
    }
}

@MainActor
struct CitySettingsView: View {
    @Bindable var usage: CityUsageMonitor
    @State private var codex = CustomScanRoots.storedValue(for: "codex") ?? ""
    @State private var claude = CustomScanRoots.storedValue(for: "claude_code") ?? ""
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("작업 도구 연동").font(.title2.bold()).foregroundStyle(TownPalette.ink)
            Text("이 Mac의 사용량 로그로 연동합니다. API 키나 계정 로그인은 필요하지 않습니다.")
                .font(.callout).foregroundStyle(.secondary)
            connection("Codex", id: "codex", automatic: "~/.codex/sessions · ~/.codex/archived_sessions", paths: $codex)
            connection("Claude Code", id: "claude_code", automatic: "~/.claude/projects · Claude 설정 경로 · Desktop 세션", paths: $claude)
            Text("추가 폴더는 기본 자동 탐색에 더해집니다. 비워서 저장하면 자동 탐색만 사용합니다. 처음 감지한 도구의 기존 사용량은 보상에서 제외됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if let message { Text(message).font(.caption).foregroundStyle(failed ? .red : TownPalette.green) }
                Spacer()
                Button(usage.isRefreshing ? "확인 중…" : "저장 및 연동 확인") {
                    do {
                        try CityConnections.save(codex: codex, claude: claude)
                        failed = false
                        message = "저장했습니다. 로그를 확인하고 있습니다."
                        Task {
                            await usage.refresh()
                            message = "확인했습니다. 기록이 없는 도구는 로그 대기 상태입니다."
                        }
                    } catch { failed = true; message = error.localizedDescription }
                }
                .disabled(usage.isRefreshing)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(28)
        .frame(width: 600)
        .background(TownPalette.paper)
    }

    private func connection(_ name: String, id: String, automatic: String, paths: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text(usage.detected.contains(id) ? "사용량 로그 감지됨" : "로그 대기 중")
                    .font(.caption).foregroundStyle(usage.detected.contains(id) ? TownPalette.green : .secondary)
            }
            Text("자동 탐색: \(automatic)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("추가 로그 폴더 (한 줄에 하나)").font(.caption)
                Spacer()
                Button("폴더 추가…") { chooseFolder(paths) }
            }
            TextEditor(text: paths)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 56)
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("\(name) 추가 로그 폴더")
            Text(id == "codex" ? "rollout-*.jsonl이 들어 있는 sessions 폴더를 선택하세요." : "프로젝트별 JSONL 로그가 들어 있는 projects 폴더를 선택하세요.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
    private func chooseFolder(_ paths: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.prompt = "로그 폴더 추가"
        guard panel.runModal() == .OK else { return }
        let existing = paths.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        paths.wrappedValue = ([existing].filter { !$0.isEmpty } + panel.urls.map(\.path)).joined(separator: "\n")
    }
}
