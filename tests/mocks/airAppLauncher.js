// Mock for @mytonwallet/air-app-launcher
const mockAirAppLauncher = {
  switchToAir: jest.fn().mockResolvedValue(undefined),
};

module.exports = {
  AirAppLauncher: mockAirAppLauncher,
};
