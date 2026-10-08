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
    static let width: CGFloat = 640
    static let height: CGFloat = 350
    static func point(_ plot: CityPlot) -> CGPoint {
        CGPoint(x: width / 2 + CGFloat(plot.column - plot.row) * 48,
                y: 130 + CGFloat(plot.row + plot.column) * 24)
    }
    var body: some View {
        ZStack {
            Canvas { context, _ in
                for depth in 0...8 {
                    for row in 0..<CityPlot.side {
                        let column = depth - row
                        guard (0..<CityPlot.side).contains(column) else { continue }
                        let plot = CityPlot(row: row, column: column)
                        let center = Self.point(plot)
                        let tile = Self.polygon([
                            .init(x: center.x, y: center.y - 22), .init(x: center.x + 44, y: center.y),
                            .init(x: center.x, y: center.y + 22), .init(x: center.x - 44, y: center.y)])
                        context.fill(tile, with: .color(Color(red: 0.77 + Double((row + column) % 2) * 0.025, green: 0.83, blue: 0.69)))
                        context.stroke(tile, with: .color(.white.opacity(0.7)), lineWidth: 1)
                        let sprout = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 3, width: 10, height: 6))
                        context.fill(sprout, with: .color(TownPalette.green.opacity(0.17)))
                    }
                }
                // Paint the entire ground before buildings so later tiles cannot cut through their bases.
                for building in buildings.sorted(by: { $0.plot.row + $0.plot.column < $1.plot.row + $1.plot.column }) {
                    guard let kind = CityBuildingKind.find(building.kindID) else { continue }
                    Self.drawBuilding(kind, at: Self.point(building.plot), selected: building.id == selected, context: &context)
                }
            }
            ForEach(0..<CityPlot.side, id: \.self) { row in
                ForEach(0..<CityPlot.side, id: \.self) { column in
                    let plot = CityPlot(row: row, column: column)
                    let building = buildings.first { $0.plot == plot }
                    Button { onSelect(plot) } label: {
                        Diamond().fill(.white.opacity(0.001))
                            .overlay(Diamond().stroke(TownPalette.green.opacity(canPlace && building == nil ? 0.4 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 88, height: 44)
                    .contentShape(Diamond())
                    .position(Self.point(plot))
                    .accessibilityLabel(building.flatMap { CityBuildingKind.find($0.kindID)?.name } ?? "빈 땅")
                    .accessibilityHint("\(row + 1)행 \(column + 1)열")
                    .help(building.flatMap { CityBuildingKind.find($0.kindID)?.name } ?? "빈 땅 · 클릭해서 건물 배치")
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(red: 0.90, green: 0.93, blue: 0.88).gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    nonisolated static func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }
    static func drawBuilding(_ kind: CityBuildingKind, at center: CGPoint, selected: Bool, context: inout GraphicsContext) {
        // The visible front corner is half a footprint depth below the tile center.
        let p = CGPoint(x: center.x, y: center.y + 14)
        let w: CGFloat = 28, d: CGFloat = 14
        let h: CGFloat = 20 + CGFloat(kind.floors) * 13
        let top = CGPoint(x: p.x, y: p.y - h)
        let left = CGPoint(x: p.x - w, y: p.y - d)
        let right = CGPoint(x: p.x + w, y: p.y - d)
        let front = CGPoint(x: p.x, y: p.y)
        let color = TownPalette.building(kind.color)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 31, y: center.y - 12, width: 62, height: 29)), with: .color(.black.opacity(0.09)))
        context.fill(polygon([left, .init(x: left.x, y: left.y - h), top, front]), with: .color(color))
        context.fill(polygon([front, top, .init(x: right.x, y: right.y - h), right]), with: .color(TownPalette.building(kind.color, shade: 0.82)))
        context.fill(polygon([top, .init(x: left.x, y: left.y - h), .init(x: p.x, y: p.y - h - d * 2), .init(x: right.x, y: right.y - h)]), with: .color(TownPalette.building(kind.color, shade: 1.18)))
        for floor in 0..<kind.floors {
            let y = p.y - 13 - CGFloat(floor) * 13
            for x: CGFloat in [-19, -9] {
                context.fill(polygon([.init(x: p.x + x, y: y + x / 2), .init(x: p.x + x + 6, y: y + x / 2 + 3),
                                      .init(x: p.x + x + 6, y: y + x / 2 - 4), .init(x: p.x + x, y: y + x / 2 - 7)]), with: .color(.white.opacity(0.85)))
            }
            for x: CGFloat in [7, 17] {
                context.fill(polygon([.init(x: p.x + x, y: y - x / 2), .init(x: p.x + x + 6, y: y - x / 2 - 3),
                                      .init(x: p.x + x + 6, y: y - x / 2 - 10), .init(x: p.x + x, y: y - x / 2 - 7)]), with: .color(.white.opacity(0.7)))
            }
        }
        if kind.floors == 1 {
            context.fill(polygon([.init(x: left.x - 3, y: left.y - h), .init(x: p.x, y: p.y - h - 40),
                                  .init(x: right.x + 3, y: right.y - h), top]), with: .color(TownPalette.ink))
        }
        if selected {
            let outline = polygon([.init(x: center.x, y: center.y - 23), .init(x: center.x + 45, y: center.y),
                                   .init(x: center.x, y: center.y + 23), .init(x: center.x - 45, y: center.y)])
            context.stroke(outline, with: .color(TownPalette.green), lineWidth: 2.5)
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        CityMapView.polygon([.init(x: rect.midX, y: rect.minY), .init(x: rect.maxX, y: rect.midY),
                             .init(x: rect.midX, y: rect.maxY), .init(x: rect.minX, y: rect.midY)])
    }
}
