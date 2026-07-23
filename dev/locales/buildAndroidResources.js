const fs = require('fs');
const path = require('path');

const { convertI18nYamlToJson } = require('./convertI18nYamlToJson');

const ROOT_DIR = path.resolve(__dirname, '../..');
const I18N_DIR = path.resolve(ROOT_DIR, 'src/i18n');
const APP_RES_SHARED_DIR = path.resolve(ROOT_DIR, 'mobile/android/app/src/main/res-shared');
const APP_I18N_ASSETS_DIR = path.resolve(ROOT_DIR, 'mobile/android/app/src/main/assets/public/i18n');

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
  const filePath = path.resolve(APP_RES_SHARED_DIR, 'xml/locales_config.xml');
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, xmlContent, 'utf8');
}

function writeI18nJsonAssets(locales) {
  ensureDir(APP_I18N_ASSETS_DIR);

  for (const fileName of fs.readdirSync(APP_I18N_ASSETS_DIR)) {
    if (fileName.endsWith('.json')) {
      fs.unlinkSync(path.resolve(APP_I18N_ASSETS_DIR, fileName));
    }
  }

  for (const locale of locales) {
    const yamlPath = ['yaml', 'yml']
      .map((extension) => path.resolve(I18N_DIR, `${locale}.${extension}`))
      .find((filePath) => fs.existsSync(filePath));
    const jsonContent = convertI18nYamlToJson(fs.readFileSync(yamlPath, 'utf8'));
    fs.writeFileSync(path.resolve(APP_I18N_ASSETS_DIR, `${locale}.json`), jsonContent, 'utf8');
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
  writeI18nJsonAssets(locales);

  console.log(`Generated Android locales_config.xml and i18n JSON assets for ${locales.length} locales.`);
}

main();
