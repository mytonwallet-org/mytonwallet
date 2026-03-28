const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const ROOT_DIR = path.resolve(__dirname, '../..');
const AIR_I18N_DIR = path.resolve(ROOT_DIR, 'src/i18n/air');
const APP_RES_DIR = path.resolve(ROOT_DIR, 'mobile/android/app/src/main/res');
const AIR_APP_RES_DIR = path.resolve(ROOT_DIR, 'mobile/android/air/app/src/main/res');

const DEFAULT_LOCALE = 'en';
const WEB_PERMISSION_KEYS = [
  '$web_permission_prompt',
  '$web_permission_allow',
  '$web_permission_deny',
  '$web_permission_camera',
  '$web_permission_microphone',
  '$web_permission_location',
  '$web_permission_device_features',
  '$web_permission_this_site',
];

const SPECIAL_LOCALE_QUALIFIERS = {
  en: 'values',
  'zh-Hans': 'values-zh-rCN',
  'zh-Hant': 'values-zh-rTW',
};

function readLocaleMap(localeFilePath) {
  const yamlContent = fs.readFileSync(localeFilePath, 'utf8');
  return yaml.load(yamlContent) || {};
}

function resolveQualifier(locale) {
  if (SPECIAL_LOCALE_QUALIFIERS[locale]) {
    return SPECIAL_LOCALE_QUALIFIERS[locale];
  }

  const [language, region] = locale.split('-');
  if (!region) {
    return `values-${language}`;
  }

  if (region.length === 2) {
    return `values-${language}-r${region.toUpperCase()}`;
  }

  return `values-${language}`;
}

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

function escapeXml(value) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/'/g, "\\'");
}

function applyAndroidPlaceholderMapping(value) {
  return value
    .replace(/%origin%/g, '%1$s')
    .replace(/%permissions%/g, '%2$s');
}

function normalizeTranslation(value) {
  return escapeXml(applyAndroidPlaceholderMapping(String(value)));
}

function renderWebPermissionXml(locale, localeMap, fallbackMap) {
  const lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<resources>',
  ];

  for (const key of WEB_PERMISSION_KEYS) {
    const resourceName = key.replace(/^\$/, '');
    const rawValue = localeMap[key] ?? fallbackMap[key];
    if (typeof rawValue !== 'string') {
      throw new Error(`Missing "${key}" for locale "${locale}" and fallback "${DEFAULT_LOCALE}"`);
    }
    lines.push(`    <string name="${resourceName}">${normalizeTranslation(rawValue)}</string>`);
  }

  lines.push('</resources>', '');
  return lines.join('\n');
}

function removeStaleWebPermissionFiles(expectedFilePaths) {
  const expected = new Set(expectedFilePaths);
  const entries = fs.readdirSync(APP_RES_DIR, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory() || !entry.name.startsWith('values')) {
      continue;
    }

    const filePath = path.resolve(APP_RES_DIR, entry.name, 'web_permission_strings.xml');
    if (fs.existsSync(filePath) && !expected.has(filePath)) {
      fs.unlinkSync(filePath);
    }
  }
}

function writeWebPermissionResources(locales, perLocale) {
  const fallbackMap = perLocale[DEFAULT_LOCALE];
  if (!fallbackMap) {
    throw new Error(`Missing required locale "${DEFAULT_LOCALE}"`);
  }

  const expectedFilePaths = [];
  for (const locale of locales) {
    const qualifier = resolveQualifier(locale);
    const localeDir = path.resolve(APP_RES_DIR, qualifier);
    const filePath = path.resolve(localeDir, 'web_permission_strings.xml');

    ensureDir(localeDir);
    fs.writeFileSync(filePath, renderWebPermissionXml(locale, perLocale[locale], fallbackMap), 'utf8');
    expectedFilePaths.push(filePath);
  }

  removeStaleWebPermissionFiles(expectedFilePaths);
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
  const targetFiles = [
    path.resolve(APP_RES_DIR, 'xml/locales_config.xml'),
    path.resolve(AIR_APP_RES_DIR, 'xml/locales_config.xml'),
  ];

  for (const filePath of targetFiles) {
    ensureDir(path.dirname(filePath));
    fs.writeFileSync(filePath, xmlContent, 'utf8');
  }
}

function loadLocales() {
  const localeFiles = fs.readdirSync(AIR_I18N_DIR)
    .filter((fileName) => fileName.endsWith('.yaml') || fileName.endsWith('.yml'))
    .map((fileName) => ({
      locale: fileName.replace(/\.(yaml|yml)$/i, ''),
      filePath: path.resolve(AIR_I18N_DIR, fileName),
    }));

  if (!localeFiles.length) {
    throw new Error(`No locale files found in ${AIR_I18N_DIR}`);
  }

  const perLocale = {};
  for (const { locale, filePath } of localeFiles) {
    perLocale[locale] = readLocaleMap(filePath);
  }

  return {
    locales: sortLocales(localeFiles.map(({ locale }) => locale)),
    perLocale,
  };
}

function main() {
  const { locales, perLocale } = loadLocales();

  writeWebPermissionResources(locales, perLocale);
  writeLocalesConfig(locales);

  console.log(`Generated Android web permission resources for ${locales.length} locales.`);
}

main();
