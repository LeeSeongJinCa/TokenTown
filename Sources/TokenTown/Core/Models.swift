import Foundation

// MARK: - ccusage daily

struct DailyUsage: Decodable, Sendable {
    var date: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var totalTokens: Int
    var totalCost: Double
    var costCoverage: CostCoverage = .source
    var usageCost: UsageCost { UsageCost(amount: totalCost, coverage: costCoverage) }
    /// totalTokens per source model when the provider reports it (nil otherwise).
    var models: [String: Int]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // ccusage ≤18 은 "date", ≥20 은 "period" 로 일자를 준다
        date = try c.decodeIfPresent(String.self, forKey: .date)
            ?? c.decodeIfPresent(String.self, forKey: .period) ?? ""
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
            ?? c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        // totalTokens 없으면 4종 토큰 합으로 폴백
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? (inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens)
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        costCoverage = try c.decodeIfPresent(CostCoverage.self, forKey: .costCoverage)
            ?? (totalTokens == 0 ? .empty : (totalCost > 0 ? .estimate : .unavailable))
        models = try c.decodeIfPresent([String: Int].self, forKey: .models)
    }

    init(date: String, inputTokens: Int, outputTokens: Int,
         cacheCreationTokens: Int, cacheReadTokens: Int, totalTokens: Int, totalCost: Double,
         models: [String: Int]? = nil, costCoverage: CostCoverage = .source) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.costCoverage = costCoverage
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case costCoverage
        case date, period, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case cachedInputTokens, totalTokens, totalCost, costUSD, models
    }
}

struct DailyReport: Decodable, Sendable {
    var daily: [DailyUsage]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daily = try c.decodeIfPresent([DailyUsage].self, forKey: .daily) ?? []
    }

    private enum CodingKeys: String, CodingKey { case daily }
}

// MARK: - ccusage blocks

struct BlockUsage: Decodable, Sendable {
    var id: String
    var startTime: String
    var endTime: String
    var isActive: Bool
    var totalTokens: Int
    var costUSD: Double
    var costCoverage: CostCoverage = .source
    var usageCost: UsageCost { UsageCost(amount: costUSD, coverage: costCoverage) }
    /// ccusage blocks 의 burnRate.tokensPerMinute — 한도 소진 예측과 companion 표시 상태에 사용
    var tokensPerMinute: Double?

    var endDate: Date? { ISO8601Parser.date(from: endTime) }

    init(id: String, startTime: String, endTime: String, isActive: Bool,
         totalTokens: Int, costUSD: Double, tokensPerMinute: Double?, costCoverage: CostCoverage = .source) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.costCoverage = costCoverage
        self.tokensPerMinute = tokensPerMinute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        costCoverage = try c.decodeIfPresent(CostCoverage.self, forKey: .costCoverage)
            ?? (totalTokens == 0 ? .empty : (costUSD > 0 ? .estimate : .unavailable))
        if let burn = try? c.decodeIfPresent(BurnRate.self, forKey: .burnRate) {
            tokensPerMinute = burn.tokensPerMinute
        }
    }

    private struct BurnRate: Decodable {
        var tokensPerMinute: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case costCoverage
        case id, startTime, endTime, isActive, totalTokens, costUSD, burnRate
    }
}

struct BlocksReport: Decodable, Sendable {
    var blocks: [BlockUsage]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decodeIfPresent([BlockUsage].self, forKey: .blocks) ?? []
    }

    private enum CodingKeys: String, CodingKey { case blocks }
}

// MARK: - ccusage weekly / monthly

struct PeriodUsage: Decodable, Sendable {
    /// 주 시작일("2026-05-31") 또는 월("2026-06")
    var period: String
    var totalTokens: Int
    var totalCost: Double
    var costCoverage: CostCoverage = .source
    var usageCost: UsageCost { UsageCost(amount: totalCost, coverage: costCoverage) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decodeIfPresent(String.self, forKey: .week)
            ?? c.decodeIfPresent(String.self, forKey: .month)
            ?? c.decodeIfPresent(String.self, forKey: .period) ?? ""
        let input = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        let output = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        let cacheW = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        let cacheR = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
            ?? c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? (input + output + cacheW + cacheR)
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        costCoverage = try c.decodeIfPresent(CostCoverage.self, forKey: .costCoverage)
            ?? (totalTokens == 0 ? .empty : (totalCost > 0 ? .estimate : .unavailable))
    }

    init(period: String, totalTokens: Int, totalCost: Double, costCoverage: CostCoverage = .source) {
        self.period = period
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.costCoverage = costCoverage
    }

    init(period: String, daily: [DailyUsage]) {
        self.period = period
        totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        totalCost = daily.reduce(0) { $0 + $1.totalCost }
        costCoverage = daily.reduce(into: .empty) { $0.merge($1.costCoverage) }
    }

    private enum CodingKeys: String, CodingKey {
        case costCoverage
        case week, month, period, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case cachedInputTokens, totalTokens, totalCost, costUSD
    }
}

struct WeeklyReport: Decodable, Sendable {
    var weekly: [PeriodUsage]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekly = try c.decodeIfPresent([PeriodUsage].self, forKey: .weekly) ?? []
    }
    private enum CodingKeys: String, CodingKey { case weekly }
}

struct MonthlyReport: Decodable, Sendable {
    var monthly: [PeriodUsage]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthly = try c.decodeIfPresent([PeriodUsage].self, forKey: .monthly) ?? []
    }
    private enum CodingKeys: String, CodingKey { case monthly }
}

// MARK: - 한도 창 길이

/// 한도 창의 길이 — 페이스(균등 소진) 기준선을 그리려면 리셋 시각만으론 부족하고 창 길이가 있어야 한다.
/// 프로바이더마다 길이를 알리는 방식이 다르므로(Codex=명시 분 수, Antigravity=창 이름, Claude=kind·필드명)
/// 변환을 여기 한 곳에 모은다 — 프로바이더 분기가 UI 로 새지 않게 하는 확장 규약.
enum ISO8601Parser {
    /// resets_at 은 마이크로초("...034464+00:00") 또는 밀리초("....303Z") 형태 — 둘 다 처리.
    /// ISO8601DateFormatter 는 non-Sendable 이라 호출마다 생성 (파싱 빈도 낮음).
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        // 소수점 자릿수가 3자리가 아니면 3자리로 절단 후 재시도
        if let dotIndex = string.firstIndex(of: ".") {
            let afterDot = string.index(after: dotIndex)
            if let tzIndex = string[afterDot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                let frac = String(string[afterDot..<tzIndex]).prefix(3)
                let padded = String(frac).padding(toLength: 3, withPad: "0", startingAt: 0)
                let rebuilt = String(string[..<dotIndex]) + "." + padded + String(string[tzIndex...])
                if let d = fractional.date(from: rebuilt) { return d }
            }
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
