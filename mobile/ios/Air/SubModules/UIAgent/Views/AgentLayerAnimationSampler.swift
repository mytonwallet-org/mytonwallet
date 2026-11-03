import UIKit
import UIComponents

/// A layer's frame at a given moment of the animations running on it, as the render server draws it then. Follows the
/// basic and spring animations UIKit runs on a view's position and bounds, whole or by component, additive or not.
@MainActor
enum AgentLayerAnimationSampler {
    /// The top of `layer`'s frame in its superlayer at `mediaTime`, or nil for a layer it can't follow: one that is
    /// transformed, or animated other than by basic or spring animations of its position and bounds
    static func getMinY(of layer: CALayer, at mediaTime: CFTimeInterval) -> CGFloat? {
        guard CATransform3DIsIdentity(layer.transform) else { return nil }
        let time = layer.convertTime(mediaTime, from: nil)
        let animations = (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) }
        guard animations.allSatisfy({ !(($0 as? CAPropertyAnimation)?.keyPath ?? "").hasPrefix("transform") }),
              let positionY = getValue(
                of: "position",
                model: layer.position.y,
                components: [
                    "position": { ($0 as? NSValue)?.cgPointValue.y },
                    "position.y": { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } },
                ],
                ignoring: ["position.x"],
                animations: animations,
                at: time
              ),
              let height = getValue(
                of: "bounds",
                model: layer.bounds.height,
                components: [
                    "bounds": { ($0 as? NSValue)?.cgRectValue.height },
                    "bounds.size": { ($0 as? NSValue)?.cgSizeValue.height },
                    "bounds.size.height": { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } },
                ],
                ignoring: ["bounds.origin", "bounds.origin.x", "bounds.origin.y", "bounds.size.width"],
                animations: animations,
                at: time
              ) else { return nil }
        return positionY - height * layer.anchorPoint.y
    }

    /// The model value of `property` with its animations applied in the order they run, as Core Animation applies
    /// them. `components` reads the value from an animation of each key path that sets it.
    private static func getValue(
        of property: String,
        model: CGFloat,
        components: [String: (Any?) -> CGFloat?],
        ignoring ignoredKeyPaths: Set<String>,
        animations: [CAAnimation],
        at time: CFTimeInterval
    ) -> CGFloat? {
        var value = model
        for animation in animations {
            guard let propertyAnimation = animation as? CAPropertyAnimation,
                  let keyPath = propertyAnimation.keyPath,
                  keyPath == property || keyPath.hasPrefix(property + "."),
                  !ignoredKeyPaths.contains(keyPath) else { continue }
            guard let component = components[keyPath],
                  let basicAnimation = propertyAnimation as? CABasicAnimation,
                  basicAnimation.beginTime > 0,
                  let from = component(basicAnimation.fromValue),
                  let to = component(basicAnimation.toValue) else { return nil }
            let duration = basicAnimation.duration > 0 ? basicAnimation.duration : 0.25
            let elapsed = (time - basicAnimation.beginTime) * CFTimeInterval(basicAnimation.speed) + basicAnimation.timeOffset
            guard elapsed >= 0, elapsed < duration else { continue }
            let animatedValue = from + (to - from) * getProgress(of: basicAnimation, elapsed: elapsed, duration: duration)
            value = basicAnimation.isAdditive ? value + animatedValue : animatedValue
        }
        return value
    }

    private static func getProgress(of animation: CABasicAnimation, elapsed: CFTimeInterval, duration: CFTimeInterval) -> CGFloat {
        if let spring = animation as? CASpringAnimation {
            var dampingRatio = spring.damping / (2 * (spring.stiffness * spring.mass).squareRoot())
            if #available(iOS 17.0, *), !spring.allowsOverdamping {
                dampingRatio = min(1, dampingRatio)
            }
            let motion = GlassSpring(dampingRatio: dampingRatio, response: 2 * .pi / (spring.stiffness / spring.mass).squareRoot())
            return motion.advance(value: 0, velocity: spring.initialVelocity, target: 1, time: CGFloat(elapsed)).value
        }
        let fraction = CGFloat(elapsed / duration)
        guard let timingFunction = animation.timingFunction else { return fraction }
        return getEasedFraction(timingFunction, at: fraction)
    }

    /// The cubic Bézier of `timingFunction` at time `fraction`
    private static func getEasedFraction(_ timingFunction: CAMediaTimingFunction, at fraction: CGFloat) -> CGFloat {
        var first: [Float] = [0, 0]
        var second: [Float] = [0, 0]
        timingFunction.getControlPoint(at: 1, values: &first)
        timingFunction.getControlPoint(at: 2, values: &second)
        func getBezier(_ t: CGFloat, _ firstControl: Float, _ secondControl: Float) -> CGFloat {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * CGFloat(firstControl) + 3 * inverse * t * t * CGFloat(secondControl) + t * t * t
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if getBezier(middle, first[0], second[0]) < fraction {
                low = middle
            } else {
                high = middle
            }
        }
        return getBezier((low + high) / 2, first[1], second[1])
    }
}
