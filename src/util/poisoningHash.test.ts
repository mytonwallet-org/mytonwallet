import type { ApiTransaction } from '../api/types';

import { makeMockTransactionActivity } from '../../tests/mocks';
import {
  clearPoisoningCache,
  getIsTransactionWithPoisoning,
  updatePoisoningCacheFromActivities,
} from './poisoningHash';

// Test addresses with different shortened forms
const VALID_ADDRESS_1 = 'EQD0vdSA_NedR9uvn89fL8n8F7pJezqhOlvjlpRThBdWNltI1234567890ABCDEF';
const VALID_ADDRESS_2 = 'EQD2vdSA_NedR9uvn89fL8n8F7pJezqhOlvjlpRThBdWNltO1234567890ABCDEF';
const SCAM_ADDRESS_1 = 'EQD0vdSA_NedR9uvn89fL8n8F7pJezqhOlvjlpRThBdWNltK1234567890ABCDEF';

// Test amounts
const LARGE_AMOUNT = BigInt(1000000000); // 1 TON
const MEDIUM_AMOUNT = BigInt(500000000); // 0.5 TON

// Test timestamps
const TIMESTAMP_1 = 1000;
const TIMESTAMP_2 = 2000;

describe('Test poison address attack', () => {
  beforeEach(() => {
    clearPoisoningCache();
  });

  describe('getIsTransactionWithPoisoning', () => {
    it('should detect scam transaction when address is poisoned', () => {
      const validActivity = makeMockTransactionActivity({
        timestamp: TIMESTAMP_1,
        amount: LARGE_AMOUNT,
        fromAddress: VALID_ADDRESS_1,
        toAddress: VALID_ADDRESS_2,
        // Incoming transaction - cache will store fromAddress
        isIncoming: true,
      });

      updatePoisoningCacheFromActivities([validActivity]);

      // Check that original transaction is not detected as scam before scam appears
      const originalTxCheck = getIsTransactionWithPoisoning(validActivity);
      expect(originalTxCheck).toBe(false);

      const scamActivity: ApiTransaction = makeMockTransactionActivity({
        timestamp: TIMESTAMP_2,
        amount: MEDIUM_AMOUNT,
        fromAddress: SCAM_ADDRESS_1,
        toAddress: VALID_ADDRESS_2,
        isIncoming: true,
      });

      const isValidScam = getIsTransactionWithPoisoning(scamActivity);

      // Scam transaction should be detected
      expect(isValidScam).toBe(true);

      // Check that original transaction is still not detected as scam after scam appears
      const originalTxCheckAfter = getIsTransactionWithPoisoning(validActivity);
      expect(originalTxCheckAfter).toBe(false);
    });

    it('should not detect transaction as scam when no cache entry exists', () => {
      const tx = makeMockTransactionActivity({
        timestamp: TIMESTAMP_1,
        amount: LARGE_AMOUNT,
        fromAddress: VALID_ADDRESS_2,
        toAddress: VALID_ADDRESS_1,
        isIncoming: false,
      });

      const isValidScam = getIsTransactionWithPoisoning(tx);

      expect(isValidScam).toBeFalsy();
    });
  });
});
