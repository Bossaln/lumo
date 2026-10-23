import SwiftUI

/// Gedächtnis-Balken: wie voll das Kontextfenster ist, ab 80 % rot.
struct ContextBar: View {
    let fraction: Double
    let color: Color
    var width: CGFloat = 44

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(SessionPalette.barTrack)
            Capsule()
                .fill(fraction >= 0.8 ? SessionPalette.barAlarm : color)
                .frame(width: max(2, width * min(max(fraction, 0), 1)))
        }
        .frame(width: width, height: 3)
    }
}

/// Prozentzahl neben dem Balken.
func contextPercent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}
