import type { AuthType } from '../global/types';
import type ElectronAuth from './auth/ElectronAuth';
import type PasscodeAuth from './auth/PasscodeAuth';
import type TelegramAuth from './auth/TelegramAuth';
import type WebAuthnAuth from './auth/WebAuthnAuth';

export type StorageKey = (
  `encryptedMasterKey:auth-${AuthType}` | `encryptedSecret#${string}`
  | 'PasscodeAuth:salt' | 'PasscodeAuth:verifierSalt' | 'PasscodeAuth:verifier'
  | 'ElectronAuth:encryptedKeyMaterial' | 'WebAuthnAuth:credentialParams'
  );
export type StorageValue = string;

export interface SimpleStorage {
  getItem: (name: StorageKey) => Promise<StorageValue | undefined>;
  setItem: (name: StorageKey, value: any) => Promise<void>;
  removeItem: (name: StorageKey) => Promise<void>;
  clear: () => Promise<void>;
  getAllKeys: () => Promise<StorageKey[]>;
}

export type AnyAuth =
  | ElectronAuth
  | PasscodeAuth
  | TelegramAuth
  | WebAuthnAuth;

export type AnyAuthClass =
  | typeof ElectronAuth
  | typeof PasscodeAuth
  | typeof TelegramAuth
  | typeof WebAuthnAuth;

export type AnyBiometricAuthClass = Exclude<AnyAuthClass, PasscodeAuth>;
