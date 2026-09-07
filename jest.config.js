const babelConfig = require('./babel.config');

module.exports = {
  setupFilesAfterEnv: ['./tests/init.ts'],
  moduleNameMapper: {
    // Match the webpack production alias: TL-B preview bundles @ton-community/tlb-runtime
    // against the app's top-level @ton/core instead of its nested copy.
    '^@ton/core(.*)$': '<rootDir>/node_modules/@ton/core$1',
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
    '<rootDir>/worktrees/',
    '<rootDir>/headless/',
    '<rootDir>/mobile/',
  ],
  // Repo copies in local worktree directories duplicate workspace packages (e.g. @mytonwallet/air-app-launcher)
  // and break jest-haste-map module resolution
  modulePathIgnorePatterns: [
    '<rootDir>/.claude/',
    '<rootDir>/worktrees/',
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
};
