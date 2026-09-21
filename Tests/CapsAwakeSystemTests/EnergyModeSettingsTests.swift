import CapsAwakeCore
import Testing

@testable import CapsAwakeSystem

@Test func parsesEnergyModePerPowerSource() {
    let output = """
        Battery Power:
         powermode            1
         displaysleep         2
        AC Power:
         powermode            0
         displaysleep         10
        """
    let modes = EnergyModeSettings.parseModes(from: output)
    #expect(modes[.battery] == .low)
    #expect(modes[.adapter] == .automatic)
}

@Test func parsesEnergyModeOnDesktopWithoutBattery() {
    let output = """
        AC Power:
         powermode            2
         sleep                0
        """
    let modes = EnergyModeSettings.parseModes(from: output)
    #expect(modes[.battery] == nil)
    #expect(modes[.adapter] == .high)
}

@Test func ignoresTheIntelLowPowerModeKey() {
    let output = """
        AC Power:
         lowpowermode         1
         sleep                0
        """
    #expect(EnergyModeSettings.parseModes(from: output).isEmpty)
}

@Test func readsHighPowerSupportFromCapabilities() {
    let output = """
        Capabilities for AC Power:
         displaysleep
         lowpowermode
         highpowermode
        """
    #expect(EnergyModeSettings.parseSupportedModes(from: output) == [.automatic, .low, .high])
}

@Test func reportsNoSupportWithoutLowPowerMode() {
    let output = """
        Capabilities for AC Power:
         displaysleep
         hibernatemode
        """
    #expect(EnergyModeSettings.parseSupportedModes(from: output).isEmpty)
}
