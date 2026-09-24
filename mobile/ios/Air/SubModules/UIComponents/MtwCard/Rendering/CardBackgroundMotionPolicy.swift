public struct CardBackgroundMotionPolicy: Equatable {
    public var requested: Bool
    public var animationsEnabled: Bool
    public var lowPowerMode: Bool
    public var reduceMotion: Bool
    public var applicationActive: Bool
    public var visible: Bool

    public init(requested: Bool, animationsEnabled: Bool, lowPowerMode: Bool, reduceMotion: Bool, applicationActive: Bool, visible: Bool) {
        self.requested = requested
        self.animationsEnabled = animationsEnabled
        self.lowPowerMode = lowPowerMode
        self.reduceMotion = reduceMotion
        self.applicationActive = applicationActive
        self.visible = visible
    }

    public var canAnimate: Bool {
        requested && animationsEnabled && !lowPowerMode && !reduceMotion && applicationActive && visible
    }
}

