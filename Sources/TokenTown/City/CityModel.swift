import Foundation

struct CityBuildingKind: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let price: Int
    let floors: Int
    let color: String
    let symbol: String

    static let catalog: [Self] = [
        .init(id: "cottage", name: "작은 집", subtitle: "모든 동네의 시작", price: 120, floors: 1, color: "coral", symbol: "house.fill"),
        .init(id: "cafe", name: "동네 카페", subtitle: "커피 향이 나는 모퉁이", price: 240, floors: 1, color: "gold", symbol: "cup.and.saucer.fill"),
        .init(id: "bookshop", name: "독립 서점", subtitle: "생각이 자라는 공간", price: 380, floors: 2, color: "mint", symbol: "books.vertical.fill"),
        .init(id: "apartment", name: "테라스 아파트", subtitle: "이웃과 함께하는 생활", price: 650, floors: 3, color: "blue", symbol: "building.2.fill"),
        .init(id: "studio", name: "크리에이티브 오피스", subtitle: "다음 아이디어의 주소", price: 950, floors: 4, color: "lavender", symbol: "building.fill"),
        .init(id: "tower", name: "랜드마크 타워", subtitle: "우리 도시의 새로운 중심", price: 1600, floors: 6, color: "teal", symbol: "building.2.crop.circle.fill")
    ]
    static func find(_ id: String) -> Self? { catalog.first { $0.id == id } }
}

struct CityPlot: Codable, Hashable, Sendable {
    let row: Int
    let column: Int
    var districtID = 0
    static let side = 5
    var isValid: Bool { (0..<Self.side).contains(row) && (0..<Self.side).contains(column) }
}

struct CityBuilding: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kindID: String
    var plot: CityPlot
    let purchasedAt: Date
    var paidCoins = 0
    var level = 1
    var upgradeCoins = 0
    var decorated = false
    var decorationCoins = 0
    var upgradePrice: Int { level * 120 }
}

enum CityDistrict: String, Codable, CaseIterable, Sendable {
    case oldTown, woodland, riverside
    var name: String {
        switch self {
        case .oldTown: "첫 동네"
        case .woodland: "숲속 지구"
        case .riverside: "강변 지구"
        }
    }
    var subtitle: String {
        switch self {
        case .oldTown: "작은 집에서 시작하는 우리 동네"
        case .woodland: "숲과 산책길이 감싸는 조용한 동네"
        case .riverside: "물결과 불빛이 만나는 동네"
        }
    }
}

struct CityRewardDay: Codable, Equatable, Sendable {
    var highWater: [String: Int] = [:]
    var eligibleTokens = 0
    var creditedCoins = 0
}

struct CityState: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    static let startingCoins = 200
    static let tokensPerCoin = 10_000
    static let dailyCoinCap = 1_000
    var version = Self.schemaVersion
    var balance = Self.startingCoins
    var lifetimeEarned = 0
    var sourceStartDays: [String: String] = [:]
    var days: [String: CityRewardDay] = [:]
    var buildings: [CityBuilding] = []
    var districts: [CityDistrict] = [.oldTown]
    var goalRewards: [String: Int] = [:]
    static let neighborGoal = "first-neighbors"
    static let neighborReward = 200
    static let decorationPrice = 50
    var goalCompleted: Bool { goalRewards[Self.neighborGoal] != nil }
    var goalEarned: Int { goalRewards.values.reduce(0, +) }
    var capacity: Int { districts.count * CityPlot.side * CityPlot.side }
    var neighborPairs: [(CityBuilding, CityBuilding)] {
        buildings.filter { $0.kindID == "cottage" }.flatMap { home in
            buildings.filter {
                $0.kindID == "cafe" && $0.plot.districtID == home.plot.districtID &&
                abs($0.plot.row - home.plot.row) + abs($0.plot.column - home.plot.column) == 1
            }.map { (home, $0) }
        }
    }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case version, balance, lifetimeEarned, sourceStartDays, days, buildings, districts, goalRewards
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let savedVersion = try values.decode(Int.self, forKey: .version)
        guard (1...Self.schemaVersion).contains(savedVersion) else { throw CityError.unsupportedVersion }
        version = Self.schemaVersion
        balance = try values.decode(Int.self, forKey: .balance)
        lifetimeEarned = try values.decode(Int.self, forKey: .lifetimeEarned)
        sourceStartDays = try values.decode([String: String].self, forKey: .sourceStartDays)
        days = try values.decode([String: CityRewardDay].self, forKey: .days)
        if savedVersion == 1 {
            // Freeze v1 prices: future catalog balancing must never alter historical purchases.
            let prices = ["cottage": 120, "cafe": 240, "bookshop": 380, "apartment": 650, "studio": 950, "tower": 1600]
            let legacy = try values.decode([LegacyBuilding].self, forKey: .buildings)
            buildings = try legacy.map { building in
                guard let price = prices[building.kindID] else { throw CityError.invalidSave }
                return CityBuilding(id: building.id, kindID: building.kindID,
                                    plot: .init(row: building.plot.row, column: building.plot.column),
                                    purchasedAt: building.purchasedAt, paidCoins: price)
            }
        } else {
            buildings = try values.decode([CityBuilding].self, forKey: .buildings)
            districts = try values.decode([CityDistrict].self, forKey: .districts)
            goalRewards = try values.decode([String: Int].self, forKey: .goalRewards)
        }
        try validate()
    }
    private struct LegacyBuilding: Decodable {
        struct Plot: Decodable { let row: Int; let column: Int }
        let id: UUID
        let kindID: String
        let plot: Plot
        let purchasedAt: Date
    }

    /// The first successful observation of each source establishes today's baseline.
    /// All subsequent days and offline increments use persistent monotonic watermarks.
    mutating func reconcile(sourceID: String, dailyTokens: [String: Int], today: String) throws {
        guard Self.isDay(today), dailyTokens.allSatisfy({ Self.isDay($0.key) && $0.value >= 0 }) else {
            throw CityError.invalidUsage
        }
        if sourceStartDays[sourceID] == nil {
            sourceStartDays[sourceID] = today
            var day = days[today, default: CityRewardDay()]
            day.highWater[sourceID] = dailyTokens[today, default: 0]
            days[today] = day
            return
        }
        let start = sourceStartDays[sourceID]!
        for key in dailyTokens.keys.sorted() where key >= start && key <= today {
            var day = days[key, default: CityRewardDay()]
            let count = dailyTokens[key]!
            let previous = day.highWater[sourceID, default: 0]
            let increase = max(0, count - previous)
            day.highWater[sourceID] = max(previous, count)
            // After reaching the cap only watermarks need to grow; bound arithmetic.
            day.eligibleTokens = min(Self.dailyCoinCap * Self.tokensPerCoin,
                                     day.eligibleTokens + min(increase, Self.dailyCoinCap * Self.tokensPerCoin))
            let earned = min(Self.dailyCoinCap, day.eligibleTokens / Self.tokensPerCoin)
            let coins = earned - day.creditedCoins
            balance += coins
            lifetimeEarned += coins
            day.creditedCoins = earned
            days[key] = day
        }
    }

    mutating func purchase(kindID: String, at plot: CityPlot, now: Date = Date()) throws {
        guard let kind = CityBuildingKind.find(kindID) else { throw CityError.unknownBuilding }
        guard plot.isValid, districts.indices.contains(plot.districtID) else { throw CityError.invalidPlot }
        guard !buildings.contains(where: { $0.plot == plot }) else { throw CityError.occupiedPlot }
        guard balance >= kind.price else { throw CityError.insufficientFunds }
        balance -= kind.price
        buildings.append(.init(id: UUID(), kindID: kindID, plot: plot, purchasedAt: now, paidCoins: kind.price))
    }

    mutating func move(buildingID: UUID, to plot: CityPlot) throws {
        guard plot.isValid, districts.indices.contains(plot.districtID) else { throw CityError.invalidPlot }
        guard let index = buildings.firstIndex(where: { $0.id == buildingID }) else { throw CityError.unknownBuilding }
        guard !buildings.contains(where: { $0.plot == plot && $0.id != buildingID }) else { throw CityError.occupiedPlot }
        buildings[index].plot = plot
    }

    mutating func claimNeighborGoal() throws {
        guard !goalCompleted, !neighborPairs.isEmpty else { throw CityError.goalUnavailable }
        goalRewards[Self.neighborGoal] = Self.neighborReward
        balance += Self.neighborReward
    }
    mutating func expand(to district: CityDistrict) throws {
        // ponytail: Two districts for this loop; add progression and a schema migration before a third.
        guard goalCompleted, districts.count == 1, district != .oldTown else { throw CityError.expansionUnavailable }
        districts.append(district)
    }
    mutating func upgrade(buildingID: UUID) throws {
        guard let index = buildings.firstIndex(where: { $0.id == buildingID }) else { throw CityError.unknownBuilding }
        guard buildings[index].level < 3 else { throw CityError.maxLevel }
        let price = buildings[index].upgradePrice
        guard balance >= price else { throw CityError.insufficientFunds }
        balance -= price
        buildings[index].upgradeCoins += price
        buildings[index].level += 1
    }
    mutating func decorate(buildingID: UUID) throws {
        guard let index = buildings.firstIndex(where: { $0.id == buildingID }) else { throw CityError.unknownBuilding }
        guard !buildings[index].decorated else { throw CityError.alreadyDecorated }
        guard balance >= Self.decorationPrice else { throw CityError.insufficientFunds }
        balance -= Self.decorationPrice
        buildings[index].decorationCoins = Self.decorationPrice
        buildings[index].decorated = true
    }

    func validate() throws {
        guard version == Self.schemaVersion else { throw CityError.unsupportedVersion }
        guard (0...100_000_000).contains(balance), (0...100_000_000).contains(lifetimeEarned),
              (1...2).contains(districts.count), districts.first == .oldTown,
              Set(districts).count == districts.count,
              buildings.count <= capacity, days.count <= 100_000,
              goalRewards.count <= 1,
              goalRewards.allSatisfy({ $0.key == Self.neighborGoal && $0.value == Self.neighborReward }),
              districts.count == 1 || goalCompleted,
              Set(buildings.map(\.id)).count == buildings.count,
              Set(buildings.map(\.plot)).count == buildings.count,
              buildings.allSatisfy({
                  $0.plot.isValid && districts.indices.contains($0.plot.districtID) && CityBuildingKind.find($0.kindID) != nil &&
                  (0...1_000_000).contains($0.paidCoins) && (1...3).contains($0.level) &&
                  (0...1_000_000).contains($0.upgradeCoins) &&
                  ($0.level == 1 ? $0.upgradeCoins == 0 : $0.upgradeCoins > 0) &&
                  ($0.decorated ? (1...1_000_000).contains($0.decorationCoins) : $0.decorationCoins == 0)
              }),
              sourceStartDays.values.allSatisfy(Self.isDay),
              days.allSatisfy({ key, day in
                  Self.isDay(key) && day.highWater.values.allSatisfy { $0 >= 0 }
                    && (0...Self.dailyCoinCap * Self.tokensPerCoin).contains(day.eligibleTokens)
                    && day.creditedCoins == day.eligibleTokens / Self.tokensPerCoin
              }) else { throw CityError.invalidSave }
        let spent = buildings.reduce(0) { $0 + $1.paidCoins + $1.upgradeCoins + $1.decorationCoins }
        guard lifetimeEarned == days.values.reduce(0, { $0 + $1.creditedCoins }),
              balance == Self.startingCoins + lifetimeEarned + goalEarned - spent else { throw CityError.invalidSave }
    }

    static func isDay(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

enum CityError: LocalizedError {
    case invalidUsage, invalidPlot, occupiedPlot, insufficientFunds, unknownBuilding, unsupportedVersion, invalidSave, readOnly, goalUnavailable, expansionUnavailable, maxLevel, alreadyDecorated
    var errorDescription: String? {
        switch self {
        case .goalUnavailable: "집과 카페를 같은 지구의 옆 땅에 놓아 주세요. 보상은 한 번만 받을 수 있습니다."
        case .expansionUnavailable: "이웃 거리 목표를 완성하면 두 번째 지구를 선택할 수 있습니다."
        case .maxLevel: "최고 단계까지 성장한 건물입니다."
        case .alreadyDecorated: "이미 나무와 벤치가 있는 건물입니다."
        case .invalidUsage: "사용량 기록의 날짜나 수량이 올바르지 않습니다."
        case .invalidPlot: "도시 바깥에는 건물을 놓을 수 없습니다."
        case .occupiedPlot: "이미 건물이 있는 땅입니다. 빈 땅을 선택해 주세요."
        case .insufficientFunds: "자금이 부족합니다. 작업을 이어가며 코인을 모아 주세요."
        case .unknownBuilding: "건물을 찾을 수 없습니다."
        case .unsupportedVersion: "더 새로운 버전의 저장 파일입니다. 파일을 보존하고 거래를 중단했습니다."
        case .invalidSave: "저장 파일을 검증할 수 없습니다. 파일을 보존하고 거래를 중단했습니다."
        case .readOnly: "저장 파일을 복구하기 전에는 도시를 변경할 수 없습니다."
        }
    }
}
