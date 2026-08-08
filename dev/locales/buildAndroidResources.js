const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const { convertI18nYamlToJson } = require('./convertI18nYamlToJson');

const ROOT_DIR = path.resolve(__dirname, '../..');
const I18N_DIR = path.resolve(ROOT_DIR, 'src/i18n');
const APP_RES_SHARED_DIR = path.resolve(ROOT_DIR, 'mobile/android/app/src/main/res-shared');
const APP_I18N_ASSETS_DIR = path.resolve(ROOT_DIR, 'mobile/android/app/src/main/assets/public/i18n');
const NATIVE_ENCLAVE_RES_DIR = path.resolve(ROOT_DIR, 'mobile/android/air/SubModules/NativeEnclave/src/main/res');

const DEFAULT_LOCALE = 'en';
const ENCLAVE_STRING_KEYS = [
  '$enclave_use_biometrics',
  '$enclave_enter_passcode_or_use_biometrics',
  '$enclave_use_pin',
  '$enclave_cancel',
];

const SPECIAL_LOCALE_QUALIFIERS = {
  en: 'values',
  'zh-Hans': 'values-zh-rCN',
  'zh-Hant': 'values-zh-rTW',
};

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

function resolveQualifier(locale) {
  if (SPECIAL_LOCALE_QUALIFIERS[locale]) {
    return SPECIAL_LOCALE_QUALIFIERS[locale];
  }

  const [language, region] = locale.split('-');
  if (!region) return `values-${language}`;
  if (region.length === 2) return `values-${language}-r${region.toUpperCase()}`;
  return `values-${language}`;
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

function escapeXml(value) {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/'/g, "\\'");
}

function renderStringsXml(locale, localeMap, fallbackMap) {
  const lines = ['<?xml version="1.0" encoding="utf-8"?>', '<resources>'];

  for (const key of ENCLAVE_STRING_KEYS) {
    const resourceName = key.replace(/^\$/, '');
    const rawValue = localeMap[key] ?? fallbackMap[key];
    if (typeof rawValue !== 'string') {
      throw new Error(`Missing key "${key}" for locale "${locale}" with no fallback in "${DEFAULT_LOCALE}"`);
    }
    lines.push(`    <string name="${resourceName}">${escapeXml(String(rawValue))}</string>`);
  }

  lines.push('</resources>', '');
  return lines.join('\n');
}

function loadLocales() {
  const localeFiles = fs.readdirSync(I18N_DIR)
    .filter((fileName) => fileName.endsWith('.yaml') || fileName.endsWith('.yml'))
    .map((fileName) => ({
      locale: fileName.replace(/\.(yaml|yml)$/i, ''),
      filePath: path.resolve(I18N_DIR, fileName),
    }));

  if (!localeFiles.length) {
    throw new Error(`No locale files found in ${I18N_DIR}`);
  }

  const perLocale = {};
  for (const { locale, filePath } of localeFiles) {
    perLocale[locale] = yaml.load(fs.readFileSync(filePath, 'utf8')) || {};
  }

  return {
    locales: sortLocales(localeFiles.map(({ locale }) => locale)),
    perLocale,
  };
}

function writeEnclaveStrings(locales, perLocale) {
  const fallbackMap = perLocale[DEFAULT_LOCALE];
  if (!fallbackMap) {
    throw new Error(`Missing required default locale "${DEFAULT_LOCALE}"`);
  }

  for (const locale of locales) {
    const localeDir = path.resolve(NATIVE_ENCLAVE_RES_DIR, resolveQualifier(locale));
    ensureDir(localeDir);
    fs.writeFileSync(
      path.resolve(localeDir, 'enclave_strings.xml'),
      renderStringsXml(locale, perLocale[locale], fallbackMap),
      'utf8',
    );
  }
}

function main() {
  const { locales, perLocale } = loadLocales();

  writeLocalesConfig(locales);
  writeI18nJsonAssets(locales);
  writeEnclaveStrings(locales, perLocale);

  console.log(`Generated Android locales_config.xml, i18n JSON assets and Enclave strings for ${locales.length} locales.`);
}

main();
