import SwiftUI

// Original centerline calligraphy. Each curve follows the pen, not a text mask.
enum LedgerInk {
    static let strokes: [Path] = {
        func stroke(_ x: CGFloat, _ y: CGFloat, _ curves: [[CGFloat]]) -> Path {
            var p = Path(); p.move(to: CGPoint(x: x, y: y))
            for c in curves { p.addCurve(to: CGPoint(x: c[4], y: c[5]), control1: CGPoint(x: c[0], y: c[1]), control2: CGPoint(x: c[2], y: c[3])) }
            return p
        }
        return [
            // L: ascending loop, descending stem, and a generous baseline flourish.
            stroke(22, 66, [[4,60,23,21,52,18],[79,15,60,55,40,69],[26,80,23,94,13,95],[1,96,9,79,29,84],[47,89,62,102,80,85]]),
            // e
            stroke(77,87, [[88,80,99,65,91,64],[80,61,71,85,80,90],[87,96,101,84,107,77]]),
            // d: oval, tall loop, return to baseline.
            stroke(120,70, [[107,58,96,87,106,91],[115,95,125,76,129,65],[135,48,149,22,144,21],[135,19,120,67,118,83],[116,101,132,88,140,77]]),
            // g: oval and descender loop.
            stroke(157,69, [[144,58,132,86,142,91],[150,96,160,78,163,67],[158,87,154,110,144,121],[132,136,124,119,140,106],[153,97,171,90,179,78]]),
            // e
            stroke(176,83, [[190,77,195,65,187,65],[176,65,169,89,181,92],[190,95,199,84,205,76]]),
            // r: rising shoulder and trailing flourish.
            stroke(202,82, [[207,75,211,65,211,65],[208,77,215,79,222,70],[226,65,230,66,226,73],[218,87,222,96,232,90],[245,85,257,77,271,80]])
        ]
    }()
}
struct LedgerInkStroke: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        LedgerInk.strokes[index].applying(CGAffineTransform(scaleX: rect.width / 280, y: rect.height / 140))
    }
}
struct HandwrittenLedger: View, Animatable {
    var progress: CGFloat = 1
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    var body: some View {
        ZStack {
            ForEach(0..<LedgerInk.strokes.count, id: \.self) { i in
                LedgerInkStroke(index: i)
                    .trim(from: 0, to: min(1, max(0, progress * 6 - CGFloat(i))))
                    .stroke(LedgerStyle.accent, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }.aspectRatio(2, contentMode: .fit).accessibilityLabel("Ledger，账本")
    }
}
