import AppKit
import SwiftUI

@MainActor
struct CityView: View {
    @Bindable var city: CityStore
    let usage: CityUsageMonitor
    @State private var blueprint: String?
    @State private var selected: UUID?
    @State private var moving = false
    @State private var showRecovery = false
    private var today: CityRewardDay { city.state.days[LocalUsageReader.todayKey(), default: CityRewardDay()] }
    private var selectedBuilding: CityBuilding? { city.state.buildings.first { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            HStack(spacing: 14) {
                metric("사용 가능한 자금", value: "\(city.state.balance.formatted())", unit: "코인", icon: "circle.hexagongrid.fill")
                metric("오늘의 작업 보상", value: "+\(today.creditedCoins.formatted())", unit: "/ \(CityState.dailyCoinCap.formatted())", icon: "sparkles")
                metric("내 도시의 건물", value: "\(city.state.buildings.count)", unit: "/ \(CityPlot.side * CityPlot.side)", icon: "building.2.fill")
            }
            HStack(alignment: .top, spacing: 24) {
                shop.frame(width: 260)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("작업으로 짓는 작은 도시").font(.system(size: 19, weight: .semibold))
                            Text(mapInstruction).font(.system(size: 12)).foregroundStyle(TownPalette.muted)
                        }
                        Spacer()
                        if blueprint != nil || moving {
                            Button("취소") { blueprint = nil; moving = false }
                                .buttonStyle(TownActionButtonStyle())
                        }
                    }
                    CityMapView(buildings: city.state.buildings, selected: selected, canPlace: blueprint != nil || moving, onSelect: selectPlot)
                    selectionPanel
                    rewardProgress
                }
            }
            footer
        }
        .padding(28)
        .frame(width: 1000, height: 880, alignment: .topLeading)
        .background(TownPalette.paper)
        .foregroundStyle(TownPalette.ink)
        .buttonStyle(.plain)
        .preferredColorScheme(.light)
        .alert("이전 저장본으로 복구할까요?", isPresented: $showRecovery) {
            Button("취소", role: .cancel) {}
            Button("복구") { city.recoverBackup() }
        } message: {
            Text("최근 거래 일부가 되돌아갈 수 있습니다. 손상된 파일은 별도로 보존합니다.")
        }
    }
    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.system(size: 36)).foregroundStyle(TownPalette.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("TokenTown").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("당신의 작업이, 당신의 동네가 됩니다.").font(.system(size: 12)).foregroundStyle(TownPalette.muted)
            }
            Spacer()
            Label("LOCAL FIRST", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(TownPalette.green)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(TownPalette.green.opacity(0.08), in: Capsule())
        }
    }
    private func metric(_ title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(TownPalette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 11)).foregroundStyle(TownPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }
    private var shop: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("새로운 이웃을 들이세요").font(.system(size: 17, weight: .semibold))
            Text("건물을 고른 뒤, 빈 땅을 클릭하세요.")
                .font(.system(size: 11)).foregroundStyle(TownPalette.muted)
            VStack(spacing: 8) {
                ForEach(CityBuildingKind.catalog) { kind in
                    Button {
                        blueprint = kind.id
                        selected = nil
                        moving = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind.symbol).font(.system(size: 22))
                                .foregroundStyle(TownPalette.building(kind.color))
                                .frame(width: 38, height: 42)
                                .background(TownPalette.building(kind.color).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.name).font(.system(size: 12, weight: .semibold))
                                Text(kind.subtitle).font(.system(size: 10)).foregroundStyle(TownPalette.muted)
                                Text("\(kind.price.formatted()) 코인").font(.system(size: 11, weight: .semibold)).foregroundStyle(TownPalette.green)
                            }
                            Spacer(minLength: 0)
                            if blueprint == kind.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(TownPalette.green) }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(city.state.balance >= kind.price ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(blueprint == kind.id ? TownPalette.green : .clear, lineWidth: 1.5))
                        .opacity(city.state.balance >= kind.price ? 1 : 0.60)
                    }
                    .buttonStyle(.plain)
                    .disabled(city.isReadOnly || city.state.balance < kind.price || city.state.buildings.count == 25)
                    .accessibilityLabel("\(kind.name), \(kind.price) 코인, 선택 후 빈 땅에 배치")
                }
            }
        }
    }
    private var mapInstruction: String {
        if moving { return "이사할 빈 땅을 클릭하세요. 이동은 무료입니다." }
        if let blueprint, let kind = CityBuildingKind.find(blueprint) { return "\(kind.name) · 빈 땅을 클릭하면 \(kind.price) 코인으로 구매합니다." }
        return "5 × 5개의 땅 · 건물이 놓인 땅을 클릭하면 자세히 볼 수 있어요."
    }
    private var selectionPanel: some View {
        HStack(spacing: 12) {
            if let building = selectedBuilding, let kind = CityBuildingKind.find(building.kindID) {
                Image(systemName: kind.symbol).foregroundStyle(TownPalette.building(kind.color))
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.name).font(.system(size: 13, weight: .semibold))
                    Text("\(building.plot.row + 1)행 \(building.plot.column + 1)열 · 구매가 \(kind.price) 코인")
                        .font(.system(size: 11)).foregroundStyle(TownPalette.muted)
                }
                Spacer()
                Button("건물 이동") { moving = true; blueprint = nil }
                    .buttonStyle(TownActionButtonStyle()).disabled(city.isReadOnly)
            } else {
                Image(systemName: "leaf.fill").foregroundStyle(TownPalette.green)
                Text(city.notice ?? (city.state.buildings.isEmpty ? "시작 자금 \(CityState.startingCoins) 코인으로 첫 집을 지어 보세요." : "건물이 놓인 땅을 클릭해서 내 이웃을 둘러보세요."))
                    .font(.system(size: 12))
                Spacer()
            }
        }
        .padding(14).frame(height: 61)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }
    private var rewardProgress: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(today.creditedCoins >= CityState.dailyCoinCap ? "오늘의 보상을 모두 받았어요" : "다음 코인까지 \((CityState.tokensPerCoin - today.eligibleTokens % CityState.tokensPerCoin).formatted()) 토큰")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(CityState.tokensPerCoin.formatted()) 토큰 = 1 코인")
                    .font(.system(size: 10)).foregroundStyle(TownPalette.muted)
            }
            GeometryReader { geometry in
                Capsule().fill(TownPalette.green.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(TownPalette.green).frame(width: geometry.size.width * (today.creditedCoins >= CityState.dailyCoinCap ? 1 : Double(today.eligibleTokens % CityState.tokensPerCoin) / Double(CityState.tokensPerCoin)))
                    }
            }.frame(height: 5)
                .accessibilityLabel("오늘 적립 보상 \(today.creditedCoins) 코인")
            Text("각 도구의 첫 감지 시점 이후 사용량부터 적립 · 캐시 포함 · 일일 합산 상한 \(CityState.dailyCoinCap.formatted()) 코인")
                .font(.system(size: 10)).foregroundStyle(TownPalette.muted)
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = city.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message).font(.system(size: 11)).lineLimit(2)
                    Spacer()
                    if city.isReadOnly { Button("백업 복구") { showRecovery = true } }
                    Button("저장 폴더") { revealSave() }
                }
                .foregroundStyle(.red)
            }
            HStack(spacing: 18) {
                ForEach(usage.sources, id: \.id) { source in
                    HStack(spacing: 5) {
                        Circle().fill(usage.detected.contains(source.id) ? TownPalette.green : TownPalette.muted.opacity(0.4)).frame(width: 5, height: 5)
                        Text(source.name).font(.system(size: 11, weight: .medium))
                        Text(usage.detected.contains(source.id) ? "오늘 \(TokenFormatter.compact(usage.todayTokens[source.id, default: 0]))" : "로그 대기 중")
                            .font(.system(size: 10)).foregroundStyle(TownPalette.muted)
                    }
                }
                Spacer()
                Button { Task { await usage.refresh() } } label: {
                    Label(usage.isRefreshing ? "읽는 중" : "새로고침", systemImage: "arrow.clockwise")
                }.buttonStyle(TownActionButtonStyle()).disabled(usage.isRefreshing || city.isReadOnly)
                Button { revealSave() } label: { Image(systemName: "folder") }.buttonStyle(TownActionButtonStyle()).help("로컬 저장 폴더 열기")
            }
            Text("로그는 이 Mac에서만 읽습니다. 가상 코인은 현금 가치가 없으며, 임대료와 자동 수익은 없습니다.")
                .font(.system(size: 10)).foregroundStyle(TownPalette.muted)
        }
    }
    private func selectPlot(_ plot: CityPlot) {
        guard !city.isReadOnly else { return }
        if let building = city.state.buildings.first(where: { $0.plot == plot }) {
            if moving { city.errorMessage = CityError.occupiedPlot.localizedDescription; return }
            selected = building.id
            blueprint = nil
        } else if moving, let selected {
            if city.move(buildingID: selected, to: plot) { moving = false }
        } else if let blueprint {
            if city.purchase(kindID: blueprint, at: plot) {
                selected = city.state.buildings.last?.id
                self.blueprint = nil
            }
        }
    }
    private func revealSave() {
        if let disk = city.persistence as? CityDiskPersistence {
            NSWorkspace.shared.open(disk.directory)
        }
    }
}

struct TownActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(TownPalette.green)
            .background(TownPalette.green.opacity(configuration.isPressed ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 7))
    }
}
