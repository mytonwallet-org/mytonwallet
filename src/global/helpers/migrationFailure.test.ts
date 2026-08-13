import type { MigrationErrorCause } from '../../enclave';

import { buildSupportCode, presentMigrationFailure } from './migrationFailure';

const CAUSE: MigrationErrorCause = { step: 'provision', name: 'TypeError', message: 'e.buffer is undefined' };

describe('presentMigrationFailure', () => {
  it('offers a retype when the password came from a keyboard', () => {
    expect(presentMigrationFailure({ kind: 'passwordOpenedNothing' })).toEqual({
      kind: 'inline',
      text: 'Wrong password, please try again.',
    });
  });

  // The password was never typed, so there is nothing to retype and a typo is not among the answers
  it('never blames a password that came from a platform store', () => {
    const presentation = presentMigrationFailure({ kind: 'passwordOpenedNothing' }, true);

    expect(presentation.kind).toBe('dialog');
    expect(presentation).toEqual({
      kind: 'dialog',
      titleKey: '$enclave_migration_damaged_title',
      messageKey: '$enclave_migration_damaged_message',
    });
  });

  it('says nothing when the person dismissed the prompt', () => {
    expect(presentMigrationFailure({ kind: 'canceled' })).toEqual({ kind: 'silent' });
  });

  // The one storage answer that is actionable, and it needs no support code to act on
  it('asks for room when the device ran out of it', () => {
    expect(presentMigrationFailure({ kind: 'storageFull' })).toEqual({
      kind: 'dialog',
      titleKey: '$enclave_migration_storage_full_title',
      messageKey: '$enclave_migration_storage_full_message',
    });
  });

  it.each([
    ['retryable', '$enclave_migration_retry_title'],
    ['blocked', '$enclave_migration_interrupted_title'],
    ['unexpected', '$enclave_migration_unexpected_title'],
  ] as const)('gives %s its own words and a code support can act on', (kind, titleKey) => {
    const presentation = presentMigrationFailure({ kind, cause: CAUSE });

    expect(presentation).toMatchObject({ kind: 'dialog', titleKey, errorCode: expect.any(String) });
  });

  // Only a cause nobody could name may be presented as one nobody could name
  it('keeps the unclassified wording for the unclassified reason alone', () => {
    const named = presentMigrationFailure({ kind: 'retryable', cause: CAUSE });
    const unnamed = presentMigrationFailure({ kind: 'unexpected', cause: CAUSE });

    expect(named).not.toMatchObject({ messageKey: '$enclave_migration_unexpected_message' });
    expect(unnamed).toMatchObject({ messageKey: '$enclave_migration_unexpected_message' });
  });
});

describe('buildSupportCode', () => {
  it('names the step and what threw', () => {
    expect(buildSupportCode(CAUSE)).toMatch(/^mig-provision-TypeError-/);
  });

  // Every TypeError at a step shares a name, so the message is what separates one report from another
  it('separates two failures that differ only in their message', () => {
    const other = { ...CAUSE, message: 'navigator.credentials is not a function' };

    expect(buildSupportCode(CAUSE)).not.toEqual(buildSupportCode(other));
  });

  it('is stable for the same cause', () => {
    expect(buildSupportCode(CAUSE)).toEqual(buildSupportCode({ ...CAUSE }));
  });

  // It is rendered into a sentence, so it stays word characters and stays short
  it('renders as a bounded word', () => {
    const code = buildSupportCode({ ...CAUSE, name: 'Not/An*Identifier '.repeat(8) });

    expect(code).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(code.length).toBeLessThanOrEqual(48);
  });
});
