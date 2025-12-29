import { PRIVATE_KEY_HEX_LENGTH } from '../config';

export default function isMnemonicPrivateKey(mnemonic: string[]): mnemonic is [string] {
  return mnemonic.length === 1 && mnemonic[0].length === PRIVATE_KEY_HEX_LENGTH;
}
