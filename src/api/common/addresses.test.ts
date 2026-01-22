import { RE_TG_BOT_MENTION } from '../../config';

// Note: `cleanText` is not exported, so we test the regex directly
// The `cleanText` function handles Unicode confusables (fake dots, etc.)

describe('RE_TG_BOT_MENTION', () => {
  beforeEach(() => {
    // Reset regex `lastIndex` (though we removed the global flag, this is good practice)
    RE_TG_BOT_MENTION.lastIndex = 0;
  });

  describe('should detect telegram bot mentions', () => {
    const scamComments = [
      // Real spam examples from testnet
      'https://t.me/tnfaucet_bot - test giver',
      '💎 tg: @buyTN_bot (get testnet TON)',

      // t.me links
      't.me/scam_channel',
      'https://t.me/free_ton',
      'http://t.me/some_bot',
      'Visit t.me/giveaway for free TON!',

      // telegram.me and telegram.dog domains
      'telegram.me/scammer',
      'https://telegram.me/fake_support',
      'telegram.dog/phishing_bot',

      // telegram: prefix variations
      'telegram: @scam_bot',
      'telegram @fake_support',
      'telegram-@phishing',
      'Telegram: @BuyTON_bot',

      // tg: prefix variations
      'tg: @scam_bot',
      'tg @fake_giveaway',
      'tg-@phishing_bot',
      'TG: @FreeCoins',
      'TG @some_channel',
    ];

    test.each(scamComments)('should match: %s', (comment) => {
      expect(RE_TG_BOT_MENTION.test(comment)).toBe(true);
    });
  });

  describe('should NOT detect legitimate content', () => {
    const legitimateComments = [
      // Normal transfer comments
      'Thanks for the payment!',
      'Invoice #12345',
      'Refund for order',
      'Payment received',

      // t.me without path (just domain mention)
      'visit t.me',
      'check out t.me for more',

      // Other URLs
      'https://google.com',
      'https://mytonwallet.io',
      'Visit our website at example.com',
    ];

    test.each(legitimateComments)('should NOT match: %s', (comment) => {
      expect(RE_TG_BOT_MENTION.test(comment)).toBe(false);
    });
  });

  describe('regex should be stateless (no global flag issue)', () => {
    it('should return consistent results on repeated calls', () => {
      const spamComment = 'https://t.me/scam_bot';

      // Call multiple times - should always return true
      expect(RE_TG_BOT_MENTION.test(spamComment)).toBe(true);
      expect(RE_TG_BOT_MENTION.test(spamComment)).toBe(true);
      expect(RE_TG_BOT_MENTION.test(spamComment)).toBe(true);
    });
  });
});
