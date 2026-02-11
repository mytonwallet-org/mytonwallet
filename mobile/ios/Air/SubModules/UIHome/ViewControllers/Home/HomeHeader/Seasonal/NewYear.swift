import Foundation
import WalletCore
import WalletContext
import SwiftUI
import UIKit

struct NewYearGarland: View {
    private struct Bulb {
        var x: CGFloat
        var y: CGFloat
        var color: Color

        static let all: [Bulb] = [
            .init(x: 8, y: 27, color: Color(red: 1.0, green: 1.0, blue: 174.0 / 255.0)),
            .init(x: 43, y: 34, color: Color(red: 1.0, green: 179.0 / 255.0, blue: 179.0 / 255.0)),
            .init(x: 74, y: 34, color: Color(red: 254.0 / 255.0, green: 251.0 / 255.0, blue: 13.0 / 255.0)),
            .init(x: 102, y: 32, color: Color(red: 10.0 / 255.0, green: 1.0, blue: 246.0 / 255.0)),
            .init(x: 129, y: 20, color: Color(red: 237.0 / 255.0, green: 163.0 / 255.0, blue: 1.0)),
            .init(x: 150, y: 32, color: Color(red: 254.0 / 255.0, green: 251.0 / 255.0, blue: 13.0 / 255.0)),
            .init(x: 179, y: 35, color: Color(red: 1.0, green: 1.0, blue: 174.0 / 255.0)),
            .init(x: 206, y: 37, color: Color(red: 1.0, green: 179.0 / 255.0, blue: 179.0 / 255.0)),
            .init(x: 232, y: 31, color: Color(red: 10.0 / 255.0, green: 1.0, blue: 246.0 / 255.0)),
            .init(x: 254, y: 21, color: Color(red: 237.0 / 255.0, green: 163.0 / 255.0, blue: 1.0)),
            .init(x: 280, y: 32, color: Color(red: 254.0 / 255.0, green: 251.0 / 255.0, blue: 13.0 / 255.0)),
            .init(x: 310, y: 38, color: Color(red: 1.0, green: 179.0 / 255.0, blue: 179.0 / 255.0)),
            .init(x: 342, y: 36, color: Color(red: 237.0 / 255.0, green: 163.0 / 255.0, blue: 1.0)),
            .init(x: 370, y: 26, color: Color(red: 1.0, green: 1.0, blue: 174.0 / 255.0)),
        ]
    }

    private let viewboxWidth: CGFloat = 378
    private let viewboxHeight: CGFloat = 72
    private let glowSize: CGFloat = 32
    private let glowBlur: CGFloat = 10
    private let onOpacity: Double = 0.6
    private let stepDuration: Double = 0.01
    private let stepPause: Duration = .milliseconds(20)

    @State private var isOn = false
    @State private var isAnimating = false
    @State private var hasPlayedInitial = false
    @State private var animationTask: Task<Void, Never>?
    @State private var opacities = Array(repeating: 0.0, count: Bulb.all.count)

    private var shouldAnimate: Bool {
        AppStorageHelper.animations
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Image(uiImage: .newYearGarland)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .top)
                bulbsLayer(size: geometry.size)
            }
        }
        .aspectRatio(viewboxWidth / viewboxHeight, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            toggle()
        }
        .onAppear {
            if !hasPlayedInitial {
                hasPlayedInitial = true
                if shouldAnimate {
                    startAnimation(turnOn: true)
                } else {
                    setAll(opacity: onOpacity)
                    isOn = true
                }
            } else {
                setAll(opacity: isOn ? onOpacity : 0)
            }
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            isAnimating = false
        }
    }

    @ViewBuilder
    private func bulbsLayer(size: CGSize) -> some View {
        let scale = min(size.width / viewboxWidth, size.height / viewboxHeight)
        let bulbSize = glowSize * scale
        let blur = glowBlur * scale
        ZStack {
            ForEach(Array(Bulb.all.enumerated()), id: \.offset) { index, bulb in
                Circle()
                    .fill(bulb.color)
                    .frame(width: bulbSize, height: bulbSize)
                    .blur(radius: blur)
                    .opacity(opacity(for: index))
                    .position(
                        x: bulb.x / viewboxWidth * size.width,
                        y: bulb.y / viewboxHeight * size.height
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func opacity(for index: Int) -> Double {
        guard opacities.indices.contains(index) else { return 0 }
        return opacities[index]
    }

    private func toggle() {
        guard !isAnimating else { return }
        startAnimation(turnOn: !isOn)
    }

    private func startAnimation(turnOn: Bool) {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            await animate(turnOn: turnOn)
        }
    }

    @MainActor
    private func animate(turnOn: Bool) async {
        guard !isAnimating else { return }
        isAnimating = true
        defer { isAnimating = false }

        if !shouldAnimate {
            setAll(opacity: turnOn ? onOpacity : 0)
            isOn = turnOn
            return
        }

        if turnOn {
            setAll(opacity: 0)
            for index in Bulb.all.indices {
                if Task.isCancelled { return }
                withAnimation(.linear(duration: stepDuration)) {
                    opacities[index] = onOpacity
                }
                try? await Task.sleep(for: stepPause)
            }
            if Task.isCancelled { return }
            setAll(opacity: onOpacity)
            isOn = true
            return
        }

        for index in Bulb.all.indices.reversed() {
            if Task.isCancelled { return }
            withAnimation(.linear(duration: stepDuration)) {
                opacities[index] = 0
            }
            try? await Task.sleep(for: stepPause)
        }
        if Task.isCancelled { return }
        setAll(opacity: 0)
        isOn = false
    }

    private func setAll(opacity: Double) {
        opacities = Array(repeating: opacity, count: Bulb.all.count)
    }
}

private extension UIImage {
    static let newYearGarland = UIImage.airBundle("NewYearGarland")
}
