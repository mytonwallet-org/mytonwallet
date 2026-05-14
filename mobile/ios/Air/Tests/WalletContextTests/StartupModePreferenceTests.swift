import Foundation
import Testing
import WalletContext

@Suite("Startup Mode Preference")
struct StartupModePreferenceTests {
    @Test
    func `missing first launch marker defaults fresh install to Air`() {
        let preference = makePreference()

        let decision = preference.applyMissingFirstLaunchMarkerPolicy(canUseClassic: true)

        #expect(decision.mode == .air)
        #expect(decision.reason == .missingFirstLaunchMarkerDefaultedToAir)
        #expect(preference.storedMode() == .air)
    }

    @Test
    func `missing first launch marker preserves explicit Classic preference`() {
        let preference = makePreference()
        preference.setMode(.classic, canUseClassic: true)

        let decision = preference.applyMissingFirstLaunchMarkerPolicy(canUseClassic: true)

        #expect(decision.mode == .classic)
        #expect(decision.reason == .missingFirstLaunchMarkerPreservedPreference)
        #expect(preference.storedMode() == .classic)
    }

    @Test
    func `Classic unavailable always resolves and persists Air`() {
        let preference = makePreference()
        preference.setMode(.classic, canUseClassic: true)

        let decision = preference.currentMode(canUseClassic: false)

        #expect(decision.mode == .air)
        #expect(decision.reason == .classicUnavailable)
        #expect(preference.storedMode() == .air)
    }

    @Test
    func `current mode uses configured default without persisting a preference`() {
        let preference = makePreference(defaultMode: .air)

        let decision = preference.currentMode(canUseClassic: true)

        #expect(decision.mode == .air)
        #expect(decision.reason == .defaultPreference)
        #expect(preference.storedMode() == nil)
    }

    @Test
    func `setting Classic while unavailable stores Air`() {
        let preference = makePreference()

        let decision = preference.setMode(.classic, canUseClassic: false)

        #expect(decision.mode == .air)
        #expect(decision.reason == .classicUnavailable)
        #expect(preference.storedMode() == .air)
    }

    @Test
    func `force Air overwrites explicit Classic`() {
        let preference = makePreference()
        preference.setMode(.classic, canUseClassic: true)

        let decision = preference.forceAir()

        #expect(decision.mode == .air)
        #expect(decision.reason == .forcedAir)
        #expect(preference.storedMode() == .air)
    }

    private func makePreference(defaultMode: StartupMode = .air) -> StartupModePreference {
        let suiteName = "StartupModePreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StartupModePreference(defaults: defaults, defaultMode: defaultMode)
    }
}
