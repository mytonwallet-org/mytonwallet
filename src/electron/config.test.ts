import fs from 'fs';
import { load } from 'js-yaml';
import path from 'path';

/*
 * `config.yml` mixes two kinds of keys: the user-visible name, which is meant to change, and the
 * bundle identity, which must survive every rebrand. They look alike, and renaming an identity key
 * fails silently — the build is green and only installed users are hurt. These tests pin the
 * identity keys so the difference is enforced rather than remembered.
 */

type ElectronBuilderConfig = {
  appId: string;
  artifactName: string;
  extraMetadata: { productName: string };
};

const config = load(
  fs.readFileSync(path.resolve(__dirname, 'config.yml'), 'utf8'),
) as ElectronBuilderConfig;

describe('Electron bundle identity', () => {
  it('keeps the name that userData and the macOS keychain entry are keyed by', () => {
    // Electron reads `app.getName()` from the packaged package.json, which `extraMetadata` writes.
    // It resolves `~/Library/Application Support/<name>` (wallets live there) and the keychain entry
    // `<name> Safe Storage` (`secrets.ts`). Renaming it orphans both, with no migration path.
    expect(config.extraMetadata.productName).toBe('MyTonWallet');
  });

  it('keeps the appId', () => {
    // Codesign identity, the NSIS registry GUID that locates the existing install directory, and the
    // bundle Squirrel.Mac looks for inside an update. Changing it means a second, parallel install.
    expect(config.appId).toBe('io.mytonwallet.electron');
  });

  it('keeps the artifact filenames in sync with the release workflow', () => {
    // Renaming is safe for installed clients (feed and files ship together per release), but the
    // workflow finds electron-builder output by these names: ARTIFACT_NAME_BASE in
    // package-and-publish.yml and the get.mywallet.io download page must move together with this.
    // eslint-disable-next-line no-template-curly-in-string
    expect(config.artifactName).toBe('MyWallet-${arch}.${ext}');
  });
});
