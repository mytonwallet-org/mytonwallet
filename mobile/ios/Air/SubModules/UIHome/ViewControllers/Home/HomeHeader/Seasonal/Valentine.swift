import Foundation
import SwiftUI
import UIKit
import WalletContext

private enum ValentineParticleKind {
    case heart
    case sparkle

    var image: UIImage {
        switch self {
        case .heart:
            return .valentinesHeart
        case .sparkle:
            return .valentinesSparkle
        }
    }
}

private struct ValentineParticle: Identifiable {
    let id = UUID()
    let kind: ValentineParticleKind
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double
    let driftX: CGFloat
    let driftY: CGFloat
    let wiggleX: CGFloat
    let wiggleY: CGFloat
    let wiggleRotation: Double
    let speed: Double
    let phase: Double
}

struct ValentineHeartsOverlay: View {
    private let swapDuration: Double = 0.4
    private let activeDuration: Double = 3.2

    @State private var baseOpacity: Double = 1
    @State private var baseBlur: CGFloat = 0
    @State private var particlesOpacity: Double = 0
    @State private var particlesBlur: CGFloat = 8
    @State private var burstStart: Date?
    @State private var particles: [ValentineParticle] = []
    @State private var sequenceTask: Task<Void, Never>?
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: .valentinesHearts)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, alignment: .top)
                .opacity(baseOpacity)
                .blur(radius: baseBlur)
                .overlay {
                    ZStack {
                        if let burstStart {
                            TimelineView(.animation) { context in
                                let elapsed = max(0, context.date.timeIntervalSince(burstStart))
                                let progress = min(1, elapsed / activeDuration)
                                ZStack {
                                    ForEach(particles) { particle in
                                        particleView(
                                            particle,
                                            size: geometry.size,
                                            elapsed: elapsed,
                                            progress: progress
                                        )
                                    }
                                }
                                .opacity(particlesOpacity)
                                .blur(radius: particlesBlur)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    start()
                }
        }
        .aspectRatio(378.0 / 72.0, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityHidden(true)
        .onDisappear {
            sequenceTask?.cancel()
            sequenceTask = nil
            isAnimating = false
        }
    }

    @ViewBuilder
    private func particleView(
        _ particle: ValentineParticle,
        size: CGSize,
        elapsed: Double,
        progress: Double
    ) -> some View {
        let phase = elapsed * particle.speed + particle.phase
        let driftX = particle.driftX * CGFloat(progress) * size.width
        let driftY = particle.driftY * CGFloat(progress) * size.height
        let wiggleX = particle.wiggleX * CGFloat(sin(phase)) * size.width
        let wiggleY = particle.wiggleY * CGFloat(cos(phase * 1.2)) * size.height
        let rotation = particle.rotation + particle.wiggleRotation * sin(phase * 1.1)
        let scale = particle.scale * (1 + 0.05 * CGFloat(sin(phase * 1.5)))
        let baseSize: CGFloat = particle.kind == .heart
            ? size.height * 0.52
            : size.height * 0.36

        Image(uiImage: particle.kind.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: baseSize * scale)
            .rotationEffect(.degrees(rotation))
            .position(
                x: particle.x * size.width + driftX + wiggleX,
                y: particle.y * size.height + driftY + wiggleY
            )
    }

    private func start() {
        guard !isAnimating else { return }
        isAnimating = true
        sequenceTask?.cancel()
        sequenceTask = Task {
            await MainActor.run {
                burstStart = Date()
                particles = makeParticles()
                particlesOpacity = 0
                particlesBlur = 8
                withAnimation(.easeInOut(duration: swapDuration)) {
                    baseOpacity = 0
                    baseBlur = 8
                    particlesOpacity = 1
                    particlesBlur = 0
                }
            }

            try? await Task.sleep(for: .seconds(activeDuration))

            await MainActor.run {
                withAnimation(.easeInOut(duration: swapDuration)) {
                    particlesOpacity = 0
                    particlesBlur = 8
                    baseOpacity = 1
                    baseBlur = 0
                }
            }

            try? await Task.sleep(for: .seconds(swapDuration))

            await MainActor.run {
                particles = []
                burstStart = nil
                isAnimating = false
            }
        }
    }

    private func makeParticles() -> [ValentineParticle] {
        let heartCount = Int.random(in: 8...12)
        let sparkleCount = Int.random(in: 8...12)
        let hearts = (0..<heartCount).map { _ in makeParticle(kind: .heart) }
        let sparkles = (0..<sparkleCount).map { _ in makeParticle(kind: .sparkle) }
        return hearts + sparkles
    }

    private func makeParticle(kind: ValentineParticleKind) -> ValentineParticle {
        ValentineParticle(
            kind: kind,
            x: .random(in: 0.06...0.94),
            y: .random(in: 0.14...0.86),
            scale: .random(in: 0.5...1.1),
            rotation: .random(in: -10...10),
            driftX: .random(in: -0.06...0.06),
            driftY: .random(in: -0.35...0.12),
            wiggleX: .random(in: 0.008...0.024),
            wiggleY: .random(in: 0.02...0.06),
            wiggleRotation: .random(in: 2...8),
            speed: .random(in: 1.2...2.2),
            phase: .random(in: 0...(Double.pi * 2))
        )
    }
}

private extension UIImage {
    static let valentinesHearts = UIImage.airBundle("ValentinesHearts")
    static let valentinesHeart = UIImage.airBundle("ValentinesHeart")
    static let valentinesSparkle = UIImage.airBundle("ValentinesSparkle")
}
