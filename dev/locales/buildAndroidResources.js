const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '../..');
const I18N_DIR = path.resolve(ROOT_DIR, 'src/i18n');
const APP_RES_SHARED_DIR = path.resolve(ROOT_DIR, 'mobile/android/app/src/main/res-shared');
const AIR_APP_RES_DIR = path.resolve(ROOT_DIR, 'mobile/android/air/app/src/main/res');

const DEFAULT_LOCALE = 'en';

function sortLocales(locales) {
  return locales.slice().sort((left, right) => {
    if (left === DEFAULT_LOCALE) {
      return -1;
    }
    if (right === DEFAULT_LOCALE) {
      return 1;
    }
    return left.localeCompare(right);
  });
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function renderLocalesConfig(locales) {
  const lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<locale-config xmlns:android="http://schemas.android.com/apk/res/android">',
  ];

  for (const locale of locales) {
    lines.push(`    <locale android:name="${locale}" />`);
  }

  lines.push('</locale-config>', '');
  return lines.join('\n');
}

function writeLocalesConfig(locales) {
  const xmlContent = renderLocalesConfig(locales);
  // `locales_config.xml` goes to the app module's `res-shared/` (shared by both
  // Air flavors) and to the Air module's own `res/`.
  const targetFiles = [
    path.resolve(APP_RES_SHARED_DIR, 'xml/locales_config.xml'),
    path.resolve(AIR_APP_RES_DIR, 'xml/locales_config.xml'),
  ];

  for (const filePath of targetFiles) {
    ensureDir(path.dirname(filePath));
    fs.writeFileSync(filePath, xmlContent, 'utf8');
  }
}

function loadLocales() {
  const locales = fs.readdirSync(I18N_DIR)
    .filter((fileName) => fileName.endsWith('.yaml') || fileName.endsWith('.yml'))
    .map((fileName) => fileName.replace(/\.(yaml|yml)$/i, ''));

  if (!locales.length) {
    throw new Error(`No locale files found in ${I18N_DIR}`);
  }

  return sortLocales(locales);
}

function main() {
  const locales = loadLocales();

  writeLocalesConfig(locales);

  console.log(`Generated Android locales_config.xml for ${locales.length} locales.`);
}

main();
