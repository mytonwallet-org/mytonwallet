import fs from 'fs';
import path from 'path';

import { convertI18nYamlToJson } from './convertI18nYamlToJson';

const ROOT_DIR = path.resolve(__dirname, '../..');
const MFA_I18N_DIR = path.resolve(ROOT_DIR, 'src/mfa/i18n');
const GENERATED_I18N_DIR = path.resolve(ROOT_DIR, 'src/mfa/i18n-generated');

export function buildMfaLocales() {
  fs.mkdirSync(GENERATED_I18N_DIR, { recursive: true });

  const langCodes = fs.readdirSync(MFA_I18N_DIR)
    .filter((fileName) => fileName.endsWith('.yaml'))
    .map((fileName) => path.basename(fileName, '.yaml'))
    .sort();

  for (const langCode of langCodes) {
    const mfaYamlPath = path.resolve(MFA_I18N_DIR, `${langCode}.yaml`);
    const generatedYamlPath = path.resolve(GENERATED_I18N_DIR, `${langCode}.yaml`);
    const generatedJsonPath = path.resolve(GENERATED_I18N_DIR, `${langCode}.json`);

    const contents = fs.readFileSync(mfaYamlPath, 'utf8');

    fs.writeFileSync(generatedYamlPath, contents, 'utf8');

    if (langCode === 'en') {
      const json = convertI18nYamlToJson(contents);
      if (!json) continue;

      fs.writeFileSync(generatedJsonPath, json, 'utf8');
    }
  }
}
