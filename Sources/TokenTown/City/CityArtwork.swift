import SwiftUI

enum TownPalette {
    static let ink = Color(red: 0.16, green: 0.23, blue: 0.25)
    static let muted = Color(red: 0.44, green: 0.49, blue: 0.48)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let green = Color(red: 0.21, green: 0.43, blue: 0.35)
    static func building(_ key: String, shade: Double = 1) -> Color {
        let rgb: (Double, Double, Double)
        switch key {
        case "coral": rgb = (0.84, 0.48, 0.39)
        case "gold": rgb = (0.88, 0.68, 0.30)
        case "mint": rgb = (0.48, 0.68, 0.53)
        case "blue": rgb = (0.47, 0.63, 0.77)
        case "lavender": rgb = (0.65, 0.58, 0.73)
        default: rgb = (0.27, 0.57, 0.56)
        }
        return Color(red: min(1, rgb.0 * shade), green: min(1, rgb.1 * shade), blue: min(1, rgb.2 * shade))
    }
}

/// Original vector artwork. No downloaded sprites, third-party assets or network requests.
@MainActor
struct CityMapView: View {
    let buildings: [CityBuilding]
    let selected: UUID?
    let canPlace: Bool
    let onSelect: (CityPlot) -> Void
    var district: CityDistrict = .oldTown
    var neighborPairs: [(CityBuilding, CityBuilding)] = []
    var night = false
    var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let width: CGFloat = 640
    static let height: CGFloat = 390
    static func point(_ plot: CityPlot) -> CGPoint {
        CGPoint(x: width / 2 + CGFloat(plot.column - plot.row) * 48,
                y: 154 + CGFloat(plot.row + plot.column) * 24)
    }
    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animate || reduceMotion || neighborPairs.isEmpty)) { timeline in
                Canvas { context, _ in
                    drawScene(context: &context, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            ForEach(0..<CityPlot.side, id: \.self) { row in
                ForEach(0..<CityPlot.side, id: \.self) { column in
                    let plot = CityPlot(row: row, column: column)
                    let building = buildings.first { $0.plot.row == row && $0.plot.column == column }
                    Button { onSelect(plot) } label: {
                        Diamond().fill(.white.opacity(0.001))
                            .overlay(Diamond().stroke(TownPalette.green.opacity(canPlace && building == nil ? 0.4 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 88, height: 44)
                    .contentShape(Diamond())
                    .position(Self.point(plot))
                    .accessibilityLabel(building.flatMap { CityBuildingKind.find($0.kindID)?.name } ?? "빈 땅")
                    .accessibilityHint(Text("\(row + 1)행 \(column + 1)열, 성장 \(building?.level ?? 0)단계"))
                    .help(building.flatMap { CityBuildingKind.find($0.kindID)?.name } ?? "빈 땅 · 클릭해서 건물 배치")
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .background {
            ZStack(alignment: .top) {
                Rectangle().fill((night ? Color(red: 0.10, green: 0.17, blue: 0.23) : Color(red: 0.90, green: 0.93, blue: 0.88)).gradient)
                if district == .woodland {
                    HStack(spacing: 30) {
                        ForEach(0..<9) { index in
                            Image(systemName: "tree.fill").font(.system(size: CGFloat(24 + index % 3 * 8)))
                                .foregroundStyle(TownPalette.green.opacity(night ? 0.5 : 0.3))
                        }
                    }.padding(.top, 34)
                } else if district == .riverside {
                    Capsule().fill(Color.cyan.opacity(night ? 0.18 : 0.22)).frame(height: 38).rotationEffect(.degrees(-8)).offset(y: 35)
                    Image(systemName: "water.waves").font(.system(size: 38)).foregroundStyle(.cyan.opacity(0.4)).offset(x: 200, y: 36)
                }
                if night {
                    HStack(spacing: 75) {
                        ForEach(0..<5) { _ in Image(systemName: "sparkle").font(.system(size: 7)).foregroundStyle(.white.opacity(0.6)) }
                        Image(systemName: "moon.fill").foregroundStyle(Color.yellow.opacity(0.8))
                    }.padding(.top, 20)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func drawScene(context: inout GraphicsContext, time: TimeInterval) {
        for depth in 0...8 {
            for row in 0..<CityPlot.side {
                let column = depth - row
                guard (0..<CityPlot.side).contains(column) else { continue }
                let plot = CityPlot(row: row, column: column)
                let center = Self.point(plot)
                let tile = Self.polygon([
                    .init(x: center.x, y: center.y - 22), .init(x: center.x + 44, y: center.y),
                    .init(x: center.x, y: center.y + 22), .init(x: center.x - 44, y: center.y)])
                context.fill(tile, with: .color(night ? Color(red: 0.23, green: 0.34, blue: 0.32) : Color(red: 0.77 + Double((row + column) % 2) * 0.025, green: 0.83, blue: 0.69)))
                context.stroke(tile, with: .color(.white.opacity(night ? 0.18 : 0.7)), lineWidth: 1)
                let sprout = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 3, width: 10, height: 6))
                context.fill(sprout, with: .color(TownPalette.green.opacity(0.17)))
            }
        }
        for (home, cafe) in neighborPairs {
            let start = Self.point(home.plot), end = Self.point(cafe.plot)
            var street = Path()
            street.move(to: .init(x: start.x, y: start.y + 20))
            street.addLine(to: .init(x: end.x, y: end.y + 20))
            context.stroke(street, with: .color(night ? .brown.opacity(0.7) : Color(red: 0.89, green: 0.84, blue: 0.69)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
        if let building = buildings.first(where: { $0.id == selected }) {
            let center = Self.point(building.plot)
            let outline = Self.polygon([.init(x: center.x, y: center.y - 23), .init(x: center.x + 45, y: center.y),
                                        .init(x: center.x, y: center.y + 23), .init(x: center.x - 45, y: center.y)])
            context.stroke(outline, with: .color(TownPalette.green), lineWidth: 2.5)
        }
        // Paint the entire ground before buildings so later tiles cannot cut through their bases.
        for building in buildings.sorted(by: { $0.plot.row + $0.plot.column < $1.plot.row + $1.plot.column }) {
            guard let kind = CityBuildingKind.find(building.kindID) else { continue }
            let center = Self.point(building.plot)
            if building.decorated { Self.drawDecoration(at: center, night: night, context: &context) }
            Self.drawBuilding(kind, at: center, context: &context,
                              level: building.level, night: night)
            if building.level > 1 {
                let floors: Int = kind.floors + building.level - 1
                let roofHeight: CGFloat = 20 + CGFloat(floors) * 13
                let badge = Text("★ Lv.\(building.level)").font(.system(size: 9, weight: .bold)).foregroundColor(night ? .yellow : TownPalette.green)
                context.draw(badge, at: CGPoint(x: center.x, y: max(12, center.y - roofHeight - 24)))
            }
        }
        for (index, pair) in neighborPairs.enumerated() {
            let start = Self.point(pair.0.plot), end = Self.point(pair.1.plot)
            let time = animate && !reduceMotion ? time : 2
            let phase = (time / 8 + Double(index) * 0.27).truncatingRemainder(dividingBy: 2)
            let progress = phase <= 1 ? phase : 2 - phase
            let point = CGPoint(x: start.x + (end.x - start.x) * progress,
                                y: start.y + 20 + (end.y - start.y) * progress)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 2, width: 6, height: 3)), with: .color(.black.opacity(0.2)))
            context.fill(Path(roundedRect: CGRect(x: point.x - 2, y: point.y - 7, width: 4, height: 6), cornerRadius: 1), with: .color(index.isMultiple(of: 2) ? .orange : .pink))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 11, width: 4, height: 4)), with: .color(Color(red: 0.96, green: 0.77, blue: 0.59)))
            let lamp = CGPoint(x: (start.x + end.x) / 2 + 8, y: (start.y + end.y) / 2 + 16)
            if night {
                context.fill(Path(ellipseIn: CGRect(x: lamp.x - 13, y: lamp.y - 17, width: 26, height: 26)), with: .color(.yellow.opacity(0.12)))
            }
            var post = Path(); post.move(to: lamp); post.addLine(to: .init(x: lamp.x, y: lamp.y - 12))
            context.stroke(post, with: .color(TownPalette.ink), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: lamp.x - 2, y: lamp.y - 14, width: 4, height: 4)), with: .color(night ? .yellow : .white))
        }
    }
    nonisolated static func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }
    static func drawDecoration(at center: CGPoint, night: Bool, context: inout GraphicsContext) {
        let trunk = CGRect(x: center.x + 32, y: center.y - 8, width: 3, height: 14)
        context.fill(Path(trunk), with: .color(.brown))
        context.fill(Path(ellipseIn: CGRect(x: center.x + 23, y: center.y - 25, width: 21, height: 24)),
                     with: .color(night ? TownPalette.green : Color(red: 0.37, green: 0.62, blue: 0.38)))
        context.fill(polygon([.init(x: center.x - 22, y: center.y + 9), .init(x: center.x - 10, y: center.y + 15),
                              .init(x: center.x - 14, y: center.y + 18), .init(x: center.x - 26, y: center.y + 12)]), with: .color(.brown))
    }
    static func drawBuilding(_ kind: CityBuildingKind, at center: CGPoint, context: inout GraphicsContext, level: Int = 1, night: Bool = false) {
        // The visible front corner is half a footprint depth below the tile center.
        let p = CGPoint(x: center.x, y: center.y + 14)
        let w: CGFloat = 28, d: CGFloat = 14
        let floors = kind.floors + level - 1
        let h: CGFloat = 20 + CGFloat(floors) * 13
        let top = CGPoint(x: p.x, y: p.y - h)
        let left = CGPoint(x: p.x - w, y: p.y - d)
        let right = CGPoint(x: p.x + w, y: p.y - d)
        let front = CGPoint(x: p.x, y: p.y)
        let color = TownPalette.building(kind.color)
        let foundation = polygon([
            .init(x: center.x, y: center.y - 17), .init(x: center.x + 34, y: center.y),
            .init(x: center.x, y: center.y + 17), .init(x: center.x - 34, y: center.y)])
        context.fill(foundation, with: .color(Color(red: 0.86, green: 0.84, blue: 0.76)))
        context.fill(polygon([left, .init(x: left.x, y: left.y - h), top, front]), with: .color(color))
        context.fill(polygon([front, top, .init(x: right.x, y: right.y - h), right]), with: .color(TownPalette.building(kind.color, shade: 0.82)))
        var contact = Path()
        contact.move(to: left)
        contact.addLine(to: front)
        contact.addLine(to: right)
        context.stroke(contact, with: .color(TownPalette.ink.opacity(0.35)), lineWidth: 1.5)
        context.fill(polygon([top, .init(x: left.x, y: left.y - h), .init(x: p.x, y: p.y - h - d * 2), .init(x: right.x, y: right.y - h)]), with: .color(TownPalette.building(kind.color, shade: 1.18)))
        for floor in 0..<floors {
            let y = p.y - 13 - CGFloat(floor) * 13
            for x: CGFloat in [-19, -9] {
                context.fill(polygon([.init(x: p.x + x, y: y + x / 2), .init(x: p.x + x + 6, y: y + x / 2 + 3),
                                      .init(x: p.x + x + 6, y: y + x / 2 - 4), .init(x: p.x + x, y: y + x / 2 - 7)]), with: .color(night ? .yellow.opacity(0.95) : .white.opacity(0.85)))
            }
            for x: CGFloat in [7, 17] {
                context.fill(polygon([.init(x: p.x + x, y: y - x / 2), .init(x: p.x + x + 6, y: y - x / 2 - 3),
                                      .init(x: p.x + x + 6, y: y - x / 2 - 10), .init(x: p.x + x, y: y - x / 2 - 7)]), with: .color(night ? .yellow.opacity(0.8) : .white.opacity(0.7)))
            }
        }
        if floors == 1 {
            context.fill(polygon([.init(x: left.x - 3, y: left.y - h), .init(x: p.x, y: p.y - h - 40),
                                  .init(x: right.x + 3, y: right.y - h), top]), with: .color(TownPalette.ink))
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        CityMapView.polygon([.init(x: rect.midX, y: rect.minY), .init(x: rect.maxX, y: rect.midY),
                             .init(x: rect.midX, y: rect.maxY), .init(x: rect.minX, y: rect.midY)])
    }
}
