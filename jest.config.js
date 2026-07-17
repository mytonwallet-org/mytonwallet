const babelConfig = require('./babel.config');

module.exports = {
  setupFilesAfterEnv: ['./tests/init.ts'],
  moduleNameMapper: {
    '\\.(css|scss|jpg|jpeg|png|gif|eot|otf|webp|svg|ttf|woff|woff2|mp4|webm|wav|mp3|m4a|aac|oga|tgs)$':
      '<rootDir>/tests/staticFileMock.js',
  },
  testPathIgnorePatterns: [
    '<rootDir>/tests/playwright/',
    '<rootDir>/node_modules/',
    '<rootDir>/client/src/stylesheets/',
    // Local-only artifacts: agent worktrees (full repo copies), headless build output,
    // SwiftPM checkouts under mobile carry their own test.js files
    '<rootDir>/.claude/',
    '<rootDir>/headless/',
    '<rootDir>/mobile/',
  ],
  // Repo copies in .claude/worktrees duplicate workspace packages (e.g. @mytonwallet/air-app-launcher)
  // and break jest-haste-map module resolution
  modulePathIgnorePatterns: [
    '<rootDir>/.claude/',
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
    '/node_modules/(?!(axios)/)',
  ],
  // Fixes https://github.com/jestjs/jest/issues/11617 (expected to be fixed properly in Jest 30.0.0)
  maxWorkers: 1,
};
