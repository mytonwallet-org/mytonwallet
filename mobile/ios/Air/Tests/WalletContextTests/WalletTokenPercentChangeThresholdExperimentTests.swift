import Testing
import WalletContext

@Suite("Wallet Token Percent Change Threshold Experiment")
struct WalletTokenPercentChangeThresholdExperimentTests {
    @Test
    func `disabled preserves all changes`() {
        let preset = WalletTokenPercentChangeThresholdExperiment.Preset.disabled

        #expect(preset.shouldShow(percentChange: 0))
        #expect(preset.shouldShow(percentChange: 0.01))
        #expect(preset.shouldShow(percentChange: -0.01))
    }

    @Test
    func `two percent threshold uses absolute value and includes boundary`() {
        let preset = WalletTokenPercentChangeThresholdExperiment.Preset.twoPercent

        #expect(!preset.shouldShow(percentChange: 1.999))
        #expect(!preset.shouldShow(percentChange: -1.999))
        #expect(preset.shouldShow(percentChange: 2))
        #expect(preset.shouldShow(percentChange: -2))
    }
}
