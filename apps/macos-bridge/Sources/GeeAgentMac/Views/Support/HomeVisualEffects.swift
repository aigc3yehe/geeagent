import SwiftUI

struct AbstractHomeBackground: View {
    @State private var animatePhase = false
    var baseOpacity: Double = 1
    var accentOpacity: Double = 1

    var body: some View {
        ZStack {
            Color(red: 0.18, green: 0.22, blue: 0.3)
                .opacity(baseOpacity)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.55, green: 0.62, blue: 0.86).opacity(0.48 * accentOpacity), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: animatePhase ? -140 : -220, y: animatePhase ? -120 : -180)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.76, green: 0.46, blue: 0.68).opacity(0.24 * accentOpacity), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 230
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: animatePhase ? 180 : 120, y: animatePhase ? 90 : 150)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.44, green: 0.78, blue: 0.88).opacity(0.16 * accentOpacity), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: animatePhase ? 230 : 170, y: animatePhase ? -180 : -120)
        }
        .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: animatePhase)
        .task {
            animatePhase = true
        }
    }
}

struct HomeRainGlassEffect: View {
    private let field = makeHomeRainGlassField()

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let time = context.date.timeIntervalSinceReferenceDate

                Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { canvas, canvasSize in
                    drawStaticDroplets(field.staticDroplets, in: &canvas, size: canvasSize)
                    drawSlidingDroplets(field.slidingDroplets, in: &canvas, size: canvasSize, time: time)
                    drawImpactRipples(field.impactRipples, in: &canvas, size: canvasSize, time: time)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawStaticDroplets(
        _ droplets: [GlassDroplet],
        in canvas: inout GraphicsContext,
        size: CGSize
    ) {
        let minSide = min(size.width, size.height)
        for droplet in droplets {
            let center = CGPoint(
                x: droplet.normalizedX * size.width,
                y: droplet.normalizedY * size.height
            )
            drawDroplet(
                center: center,
                radius: droplet.radius * minSide,
                opacity: droplet.opacity,
                canvas: &canvas
            )
        }
    }

    private func drawSlidingDroplets(
        _ droplets: [SlidingDroplet],
        in canvas: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let minSide = min(size.width, size.height)
        for droplet in droplets {
            let cyclePosition =
                (droplet.phase + time / droplet.duration).truncatingRemainder(dividingBy: 1.0)
            let y = (droplet.startY + cyclePosition * (droplet.endY - droplet.startY)) * size.height
            let x = droplet.normalizedX * size.width
            let radius = droplet.radius * minSide

            let trailFade = sin(cyclePosition * .pi)
            if trailFade > 0.08 {
                let trailHeight = droplet.trailLength * size.height * trailFade
                let trailRect = CGRect(
                    x: x - radius * 0.2,
                    y: y - trailHeight,
                    width: radius * 0.4,
                    height: trailHeight
                )
                canvas.fill(
                    Path(roundedRect: trailRect, cornerRadius: radius * 0.2),
                    with: .color(Color.white.opacity(droplet.opacity * 0.12 * trailFade))
                )
            }

            drawDroplet(
                center: CGPoint(x: x, y: y),
                radius: radius,
                opacity: droplet.opacity,
                canvas: &canvas
            )
        }
    }

    private func drawImpactRipples(
        _ ripples: [ImpactRipple],
        in canvas: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let minSide = min(size.width, size.height)
        for ripple in ripples {
            let cycle =
                (ripple.phase + time / ripple.duration).truncatingRemainder(dividingBy: 1.0)

            guard cycle < 0.45 else { continue }

            let progress = cycle / 0.45
            let peakRadius = ripple.peakRadius * minSide
            let radius = peakRadius * progress
            let alpha = (1 - progress) * ripple.opacity

            let center = CGPoint(
                x: ripple.normalizedX * size.width,
                y: ripple.normalizedY * size.height
            )
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            canvas.stroke(
                Path(ellipseIn: rect),
                with: .color(Color.white.opacity(alpha * 0.55)),
                lineWidth: max(0.6, peakRadius * 0.04)
            )

            if progress < 0.35 {
                let coreRect = rect.insetBy(dx: radius * 0.7, dy: radius * 0.7)
                canvas.fill(
                    Path(ellipseIn: coreRect),
                    with: .color(Color.white.opacity(alpha * 0.35))
                )
            }
        }
    }

    private func drawDroplet(
        center: CGPoint,
        radius: CGFloat,
        opacity: Double,
        canvas: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = Path(ellipseIn: rect)

        canvas.fill(path, with: .color(Color.white.opacity(opacity * 0.16)))
        canvas.stroke(
            path,
            with: .color(Color.white.opacity(opacity * 0.42)),
            lineWidth: max(0.55, radius * 0.06)
        )

        let highlightRect = CGRect(
            x: rect.midX - radius * 0.44,
            y: rect.midY - radius * 0.5,
            width: radius * 0.55,
            height: radius * 0.42
        )
        canvas.fill(
            Path(ellipseIn: highlightRect),
            with: .color(Color.white.opacity(opacity * 0.38))
        )
    }
}

struct HomeRainGlassField {
    let staticDroplets: [GlassDroplet]
    let slidingDroplets: [SlidingDroplet]
    let impactRipples: [ImpactRipple]
}

struct GlassDroplet {
    let normalizedX: Double
    let normalizedY: Double
    let radius: Double
    let opacity: Double
}

struct SlidingDroplet {
    let normalizedX: Double
    let startY: Double
    let endY: Double
    let radius: Double
    let opacity: Double
    let duration: Double
    let phase: Double
    let trailLength: Double
}

struct ImpactRipple {
    let normalizedX: Double
    let normalizedY: Double
    let peakRadius: Double
    let opacity: Double
    let duration: Double
    let phase: Double
}

func makeHomeRainGlassField(seed: UInt64 = 0x4745455241494E) -> HomeRainGlassField {
    var generator = SeededGenerator(state: seed)

    func random(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + generator.nextUnit() * (range.upperBound - range.lowerBound)
    }

    let staticDroplets = (0..<9).map { _ in
        GlassDroplet(
            normalizedX: random(0.06...0.94),
            normalizedY: random(0.08...0.92),
            radius: random(0.006...0.014),
            opacity: random(0.42...0.72)
        )
    }

    let slidingDroplets = (0..<3).map { _ in
        SlidingDroplet(
            normalizedX: random(0.12...0.88),
            startY: random(-0.12...0.1),
            endY: random(0.9...1.15),
            radius: random(0.008...0.013),
            opacity: random(0.48...0.7),
            duration: random(7.5...14.0),
            phase: random(0...1),
            trailLength: random(0.04...0.1)
        )
    }

    let impactRipples = (0..<4).map { _ in
        ImpactRipple(
            normalizedX: random(0.12...0.88),
            normalizedY: random(0.12...0.88),
            peakRadius: random(0.025...0.05),
            opacity: random(0.45...0.75),
            duration: random(5.5...9.5),
            phase: random(0...1)
        )
    }

    return HomeRainGlassField(
        staticDroplets: staticDroplets,
        slidingDroplets: slidingDroplets,
        impactRipples: impactRipples
    )
}

private struct SeededGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }

    mutating func nextUnit() -> Double {
        Double(next() % 10_000) / 10_000.0
    }
}
