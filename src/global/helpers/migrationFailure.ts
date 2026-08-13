import type { MigrationErrorCause, MigrationFailureReason } from '../../enclave';
import type { MigrationErrorPresentation } from '../types';

/**
 * The one place a stopped migration is turned into words. A reason the migration did establish is
 * answered on what it established; only a reason nobody could name says so out loud. No message
 * here ends with the legacy ciphertext, the only remaining copy of the wallets, being erased.
 */
export function presentMigrationFailure(
  reason: MigrationFailureReason,
  isPasswordFromStore = false,
): MigrationErrorPresentation {
  switch (reason.kind) {
    case 'passwordOpenedNothing':
      // A password out of a platform store was never typed, so a typo is not among the explanations
      return isPasswordFromStore
        ? {
          kind: 'dialog',
          titleKey: '$enclave_migration_damaged_title',
          messageKey: '$enclave_migration_damaged_message',
        }
        : { kind: 'inline', text: 'Wrong password, please try again.' };

    // Dismissing a prompt is an answer, not a fault, and the screen already offers the way back in
    case 'canceled':
      return { kind: 'silent' };

    case 'storageFull':
      return {
        kind: 'dialog',
        titleKey: '$enclave_migration_storage_full_title',
        messageKey: '$enclave_migration_storage_full_message',
      };

    case 'retryable':
      return {
        kind: 'dialog',
        titleKey: '$enclave_migration_retry_title',
        messageKey: '$enclave_migration_retry_message',
        errorCode: buildSupportCode(reason.cause),
      };

    case 'blocked':
      return {
        kind: 'dialog',
        titleKey: '$enclave_migration_interrupted_title',
        messageKey: '$enclave_migration_interrupted_message',
        errorCode: buildSupportCode(reason.cause),
      };

    case 'unexpected':
      return {
        kind: 'dialog',
        titleKey: '$enclave_migration_unexpected_title',
        messageKey: '$enclave_migration_unexpected_message',
        errorCode: buildSupportCode(reason.cause),
      };
  }
}

/**
 * Reads as `mig-provision-TypeError-8fa1`. Stripped of anything but word characters, because it is
 * rendered. The trailing digest stands in for the message: every `TypeError` at a step shares a name,
 * and without it an extension that shimmed the credentials API and a null dereference in storage
 * reach support under the same code.
 */
export function buildSupportCode({ step, name, message }: MigrationErrorCause) {
  const digest = hashMessage(message);

  return `mig-${step}-${name.replace(/[^A-Za-z0-9_]/g, '')}`.slice(0, 42) + `-${digest}`;
}

function hashMessage(message: string) {
  let hash = 0;

  for (let i = 0; i < message.length; i++) {
    hash = (Math.imul(hash, 31) + message.charCodeAt(i)) | 0;
  }

  return (hash >>> 0).toString(36).padStart(4, '0').slice(-4);
}
