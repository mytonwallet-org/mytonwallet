const babelConfig = require('./babel.config');

module.exports = {
  setupFilesAfterEnv: ['./tests/init.ts'],
  moduleNameMapper: {
    '\\.(css|scss|jpg|jpeg|png|gif|eot|otf|webp|svg|ttf|woff|woff2|mp4|webm|wav|mp3|m4a|aac|oga|tgs)$':
      '<rootDir>/tests/staticFileMock.js',
    '@mytonwallet/air-app-launcher': '<rootDir>/tests/mocks/airAppLauncher.js',
    '@mauricewegner/capacitor-navigation-bar': '<rootDir>/tests/mocks/capacitorNavigationBar.js',
  },
  testPathIgnorePatterns: [
    '<rootDir>/tests/playwright/',
    '<rootDir>/node_modules/',
    '<rootDir>/client/src/stylesheets/',
  ],
  testEnvironment: 'jest-environment-jsdom',
  transform: {
    '\\.(jsx?|tsx?)$': ['babel-jest', {
      ...babelConfig,
      plugins: [...babelConfig.plugins, 'babel-plugin-transform-import-meta'],
    }],
    '\\.txt$': 'jest-raw-loader',
  },
  transformIgnorePatterns: [
    '/node_modules/(?!(axios|@capgo)/)',
  ],
  // Fixes https://github.com/jestjs/jest/issues/11617 (expected to be fixed properly in Jest 30.0.0)
  maxWorkers: 1,
};
