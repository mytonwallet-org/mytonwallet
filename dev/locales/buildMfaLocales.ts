import fs from 'fs';
import path from 'path';

import { convertI18nYamlToJson } from './convertI18nYamlToJson';

const ROOT_DIR = path.resolve(__dirname, '../..');
const MAIN_I18N_DIR = path.resolve(ROOT_DIR, 'src/i18n');
const MFA_I18N_DIR = path.resolve(ROOT_DIR, 'src/mfa/i18n');
const GENERATED_I18N_DIR = path.resolve(ROOT_DIR, 'src/mfa/i18n-generated');

const LANG_CODES = ['en', 'ru'];

export function buildMfaLocales() {
  fs.mkdirSync(GENERATED_I18N_DIR, { recursive: true });

  for (const langCode of LANG_CODES) {
    const mainYamlPath = path.resolve(MAIN_I18N_DIR, `${langCode}.yaml`);
    const mfaYamlPath = path.resolve(MFA_I18N_DIR, `${langCode}.yaml`);
    const generatedYamlPath = path.resolve(GENERATED_I18N_DIR, `${langCode}.yaml`);
    const generatedJsonPath = path.resolve(GENERATED_I18N_DIR, `${langCode}.json`);

    const contents = [
      fs.readFileSync(mainYamlPath, 'utf8'),
      fs.existsSync(mfaYamlPath) ? fs.readFileSync(mfaYamlPath, 'utf8') : '',
    ].filter(Boolean).join('\n');

    fs.writeFileSync(generatedYamlPath, contents, 'utf8');

    const json = convertI18nYamlToJson(contents);
    if (json) {
      fs.writeFileSync(generatedJsonPath, json, 'utf8');
    }
  }
}
