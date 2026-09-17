import fileNamingPlugin, { FILE_NAMING_RULE } from './fileNamingPlugin.mjs';
const FILE_NAMING_IGNORES = [
  'src/lib/**', 'src/**/generated/**', 'src/api/migrations/+([0-9]).ts', '**/_*.module.scss',
];

export default [
  {
    files: ['src/**/*.{js,jsx,ts,tsx}', 'src/**/*.module.scss'],
    // Library entrypoints retain their upstream and integration naming conventions
    ignores: FILE_NAMING_IGNORES,
    plugins: { 'file-naming': fileNamingPlugin },
    rules: {
      [FILE_NAMING_RULE]: ['error', 'mixedCase'],
    },
  },
  {
    files: ['src/**/components/**/*.{jsx,tsx}', 'src/**/components/**/*.module.scss'],
    ignores: [...FILE_NAMING_IGNORES, '**/hooks/**', '**/helpers/**', '**/index.{jsx,tsx}'],
    rules: {
      [FILE_NAMING_RULE]: ['error', 'pascalCase'],
    },
  },
  {
    files: ['src/**/hooks/*.{js,jsx,ts,tsx}'],
    ignores: FILE_NAMING_IGNORES,
    rules: {
      [FILE_NAMING_RULE]: ['error', 'camelCase'],
    },
  },
  {
    files: ['src/**/*.module.scss'],
    plugins: { 'file-naming': fileNamingPlugin },
    processor: 'file-naming/filename',
  },
];
