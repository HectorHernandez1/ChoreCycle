import SwiftUI

/// One celebration: either a small pop of confetti at a point (a single
/// chore finished) or a full-width shower from the top (everything done).
struct ConfettiBurst: Identifiable {
    enum Kind {
        case pop(at: CGPoint)
        case shower
    }

    let id = UUID()
    let kind: Kind
    let startDate: Date

    /// Seeds the per-particle randomness so every frame draws the same
    /// particles in the same colors; only time moves them.
    let seed = UInt64.random(in: .min ... .max)

    /// `startDate` is only overridden by previews, to show a burst mid-flight.
    init(kind: Kind, startDate: Date = .now) {
        self.kind = kind
        self.startDate = startDate
    }

    var duration: TimeInterval {
        switch kind {
        case .pop: 1.4
        case .shower: 3.5
        }
    }

    var particleCount: Int {
        switch kind {
        case .pop: 32
        case .shower: 180
        }
    }
}

/// Draws every active `ConfettiBurst`. Designed to sit in an `.overlay` on
/// top of the chore list; it never intercepts touches.
///
/// Particles are not stored anywhere. Each frame, their position is
/// recomputed from a seeded random generator plus the time elapsed since
/// the burst started, which keeps this cheap even with hundreds of pieces.
struct ConfettiOverlay: View {
    let bursts: [ConfettiBurst]
    /// The app's accent color, mixed into the confetti so it matches the
    /// rest of the UI.
    var accent: Color = .teal

    private var palette: [Color] {
        [accent, .pink, .yellow, .orange, .purple, .blue, .mint, .red]
    }

    var body: some View {
        // `.animation` redraws every frame, but pauses when there's nothing
        // to show so an idle list costs nothing.
        TimelineView(.animation(paused: bursts.isEmpty)) { timeline in
            Canvas { context, size in
                for burst in bursts {
                    draw(burst, at: timeline.date, in: &context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ burst: ConfettiBurst, at date: Date, in context: inout GraphicsContext, size: CGSize) {
        let elapsed = date.timeIntervalSince(burst.startDate)
        guard elapsed >= 0, elapsed < burst.duration else { return }

        for index in 0..<burst.particleCount {
            var rng = SeededGenerator(seed: burst.seed ^ (UInt64(index) &* 0xD1B5_4A32_D192_ED03))

            // Appearance: pulled from the generator in a fixed order so each
            // particle looks the same from frame to frame.
            let color = palette[Int.random(in: 0..<palette.count, using: &rng)]
            let width = CGFloat.random(in: 6...11, using: &rng)
            let height = width * CGFloat.random(in: 0.45...1.0, using: &rng)
            let isRound = Int.random(in: 0..<4, using: &rng) == 0
            let spin = Double.random(in: -7...7, using: &rng)
            let flipSpeed = Double.random(in: 4...9, using: &rng)
            let phase = Double.random(in: 0..<(2 * .pi), using: &rng)

            // Motion: where the piece starts, how fast it leaves, and how
            // hard gravity and air resistance act on it.
            let origin: CGPoint
            let velocity: CGVector
            let gravity: Double
            let drag: Double
            let delay: Double
            switch burst.kind {
            case .pop(let point):
                origin = point
                let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                let speed = Double.random(in: 240...560, using: &rng)
                // Bias upward a little so the pop feels like it jumps out.
                velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 140)
                gravity = 950
                drag = 3.2
                delay = 0
            case .shower:
                origin = CGPoint(
                    x: .random(in: 0...size.width, using: &rng),
                    y: -.random(in: 10...80, using: &rng)
                )
                velocity = CGVector(
                    dx: .random(in: -50...50, using: &rng),
                    dy: .random(in: 60...200, using: &rng)
                )
                gravity = 240
                drag = 0.8
                // Stagger the start so the shower keeps coming for a moment.
                delay = .random(in: 0...1.0, using: &rng)
            }

            let t = elapsed - delay
            guard t > 0 else { continue }
            let life = t / (burst.duration - delay)
            guard life < 1 else { continue }

            // Launch velocity decays with drag while gravity keeps pulling.
            let travel = (1 - exp(-drag * t)) / drag
            let flutter = sin(t * flipSpeed * 0.6 + phase) * 8
            let x = origin.x + velocity.dx * travel + flutter
            let y = origin.y + velocity.dy * travel + 0.5 * gravity * t * t

            // Fade out over the last 30% of the particle's life, and fake a
            // 3D tumble by squashing the width with a cosine.
            let alpha = min(1, (1 - life) / 0.3)
            let rotation = Angle.radians(phase + spin * t)
            let flip = max(0.15, abs(cos(t * flipSpeed + phase)))

            var piece = context
            piece.opacity = alpha
            piece.translateBy(x: x, y: y)
            piece.rotate(by: rotation)
            piece.scaleBy(x: flip, y: 1)

            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            let path = isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
            piece.fill(path, with: .color(color))
        }
    }
}

/// A tiny deterministic random number generator (SplitMix64). Given the
/// same seed it always produces the same sequence, which is what lets the
/// confetti be redrawn from scratch each frame.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    // Start both bursts a moment in the past so the snapshot catches them
    // mid-flight instead of before anything has entered the screen.
    ConfettiOverlay(bursts: [
        ConfettiBurst(kind: .shower, startDate: .now.addingTimeInterval(-1.5)),
        ConfettiBurst(kind: .pop(at: CGPoint(x: 120, y: 400)), startDate: .now.addingTimeInterval(-0.3))
    ])
}
