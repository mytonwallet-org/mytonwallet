import {
  convertExplorerUrl,
  getAgentNewsShareUrl,
  getExplorerAddressUrl,
  getExplorerTransactionUrl,
  getViewAccountUrl,
  getViewTokenUrl,
  isInIframeWhitelist,
  isValidUrl,
  normalizeUrl,
} from './url';

// Test constants
const TEST_TON_ADDRESS = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
const TEST_TRON_ADDRESS = 'TRjE1H8dxypKM1NZRdysbs9wo7huR4bdNz';
const TEST_SOLANA_ADDRESS = '6fHx3tfJdMz7NEjjSdzFy18byg328vnrNH5Z23zGprKL';
const TEST_EVM_ADDRESS = '0x9429C8Af1089efD542b313156Af2DFA35c7e0a81';
const TEST_TON_HASH = 'cd3547d822b1f33e5825572709b9ac95e64d46680cde5fc6e5ae489ecec83b27';
const TEST_MESSAGE_HASH = 'f0ba363519a627caeda1d41d8cc7c14ba21287e719e3a8b424471e49daffcc11';
const TEST_EVM_HASH = '0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060';
const TEST_NFT_ADDRESS = 'EQCchzdeVwH5js22ReWU7smONvgpB9bZG9k_VEmYmGhIhuTL';
const TEST_NFT_COLLECTION_ADDRESS = 'EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM';

describe('isValidUrl', () => {
  it('should return true for valid urls', () => {
    expect(isValidUrl('https://www.google.com')).toBe(true);
    expect(isValidUrl('http://localhost')).toBe(true);
    expect(isValidUrl('http://localhost:3000')).toBe(true);
    expect(isValidUrl('https://what-about-non-ascii.рф')).toBe(true);
    expect(isValidUrl('http://127.0.0.1:3000')).toBe(true);
  });

  it('should return false for invalid urls', () => {
    expect(isValidUrl('https://fragment')).toBe(false);
    expect(isValidUrl('https://@push')).toBe(false);
    expect(isValidUrl('https://what is push?')).toBe(false);
    expect(isValidUrl('https://what is push.')).toBe(false);
    expect(isValidUrl('javascript:alert("Hello, world!")')).toBe(false);
    // eslint-disable-next-line @stylistic/max-len
    expect(isValidUrl('data:image/svg+xml,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20onload%3D%27alert(1)%27%3E%3C%2Fsvg%3E')).toBe(false);
    expect(isValidUrl('file://localhost/path/to/file')).toBe(false);
  });
});

describe('normalizeUrl', () => {
  it('should add https:// prefix when protocol is missing', () => {
    expect(normalizeUrl('example.com')).toBe('https://example.com');
    expect(normalizeUrl('my.tt/view/?ton=123')).toBe('https://my.tt/view/?ton=123');
    expect(normalizeUrl('subdomain.example.com/path')).toBe('https://subdomain.example.com/path');
  });

  it('should convert http:// to https://', () => {
    expect(normalizeUrl('http://example.com')).toBe('https://example.com');
    expect(normalizeUrl('http://my.tt/view/?ton=123')).toBe('https://my.tt/view/?ton=123');
  });

  it('should not modify URLs that already have https:// protocol', () => {
    expect(normalizeUrl('https://example.com')).toBe('https://example.com');
    expect(normalizeUrl('https://my.tt/view/?ton=123&tron=456')).toBe('https://my.tt/view/?ton=123&tron=456');
  });

  it('should handle URLs with query parameters and fragments', () => {
    expect(normalizeUrl('example.com/path?query=value#fragment'))
      .toBe('https://example.com/path?query=value#fragment');
    const deeplinkUrl = `my.tt/view/?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`;
    const expectedUrl = `https://my.tt/view/?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`;
    expect(normalizeUrl(deeplinkUrl)).toBe(expectedUrl);
  });

  it('should handle empty string', () => {
    expect(normalizeUrl('')).toBe('https://');
  });
});

describe('getViewAccountUrl', () => {
  it('should collapse matching EVM chain addresses into the evm parameter', () => {
    expect(getViewAccountUrl({
      ethereum: TEST_EVM_ADDRESS,
      solana: TEST_SOLANA_ADDRESS,
      ton: TEST_TON_ADDRESS,
      tron: TEST_TRON_ADDRESS,
      bnb: TEST_EVM_ADDRESS,
      hyperliquid: TEST_EVM_ADDRESS,
      robinhood: TEST_EVM_ADDRESS,
      arc: TEST_EVM_ADDRESS,
      base: TEST_EVM_ADDRESS,
      arbitrum: TEST_EVM_ADDRESS,
      optimism: TEST_EVM_ADDRESS,
      monad: TEST_EVM_ADDRESS,
      polygon: TEST_EVM_ADDRESS,
      avalanche: TEST_EVM_ADDRESS,
    })).toBe(
      `https://my.tt/view/?evm=${TEST_EVM_ADDRESS}&solana=${TEST_SOLANA_ADDRESS}`
      + `&ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`,
    );
  });

  it('should keep concrete EVM chain parameters when the EVM set is incomplete', () => {
    expect(getViewAccountUrl({
      ethereum: TEST_EVM_ADDRESS,
      base: TEST_EVM_ADDRESS,
      ton: TEST_TON_ADDRESS,
    })).toBe(
      `https://my.tt/view/?ethereum=${TEST_EVM_ADDRESS}&base=${TEST_EVM_ADDRESS}&ton=${TEST_TON_ADDRESS}`,
    );
  });

  it('should keep testnet parameter after the collapsed EVM parameter', () => {
    expect(getViewAccountUrl({
      ethereum: TEST_EVM_ADDRESS,
      base: TEST_EVM_ADDRESS,
      bnb: TEST_EVM_ADDRESS,
      polygon: TEST_EVM_ADDRESS,
      arbitrum: TEST_EVM_ADDRESS,
      optimism: TEST_EVM_ADDRESS,
      monad: TEST_EVM_ADDRESS,
      avalanche: TEST_EVM_ADDRESS,
      hyperliquid: TEST_EVM_ADDRESS,
      robinhood: TEST_EVM_ADDRESS,
      arc: TEST_EVM_ADDRESS,
    }, true)).toBe(`https://my.tt/view/?evm=${TEST_EVM_ADDRESS}&testnet=true`);
  });
});

describe('getViewTokenUrl', () => {
  it('should address a token by its chain and contract address', () => {
    expect(getViewTokenUrl({ chain: 'ton', slug: 'ton-eqaisixsrb', tokenAddress: TEST_TON_ADDRESS }))
      .toBe(`https://my.tt/token/ton/${TEST_TON_ADDRESS}`);
  });

  it('should address a native coin by its slug', () => {
    expect(getViewTokenUrl({ chain: 'ton', slug: 'toncoin' })).toBe('https://my.tt/token/toncoin');
  });

  it('should add the testnet parameter', () => {
    expect(getViewTokenUrl({ chain: 'ton', slug: 'toncoin' }, true)).toBe('https://my.tt/token/toncoin?testnet=true');
  });
});

describe('getAgentNewsShareUrl', () => {
  it.each([
    [7, 'en', 'https://my.tt/agent?news=7&lang=en&utm_source=pulse_share'],
    [2147483647, 'ru', 'https://my.tt/agent?news=2147483647&lang=ru&utm_source=pulse_share'],
  ] as const)('should link news %d shown in %s', (eventId, locale, url) => {
    expect(getAgentNewsShareUrl(eventId, locale)).toBe(url);
  });
});

describe('convertExplorerUrl', () => {
  describe('TON explorer conversions (mainnet)', () => {
    it('should convert address URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert address URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      const expected = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert transaction URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/tx/${TEST_TON_HASH}`;
      const expected = `https://tonviewer.com/transaction/${TEST_TON_HASH}`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert transaction URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/transaction/${TEST_TON_HASH}`;
      const expected = `https://tonscan.org/tx/${TEST_TON_HASH}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert NFT URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/nft/${TEST_NFT_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_NFT_ADDRESS}?nft`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert NFT URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_NFT_ADDRESS}?nft`;
      const expected = `https://tonscan.org/nft/${TEST_NFT_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert NFT collection URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/collection/${TEST_NFT_COLLECTION_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_NFT_COLLECTION_ADDRESS}?collection`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert NFT collection URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_NFT_COLLECTION_ADDRESS}?collection`;
      const expected = `https://tonscan.org/collection/${TEST_NFT_COLLECTION_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert token/jetton URL from Tonscan to Tonviewer', () => {
      const input = `https://tonscan.org/jetton/${TEST_TON_ADDRESS}`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?jetton`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert token/jetton URL from Tonviewer to Tonscan', () => {
      const input = `https://tonviewer.com/${TEST_TON_ADDRESS}?jetton`;
      const expected = `https://tonscan.org/jetton/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });
  });

  describe('TON explorer conversions (testnet)', () => {
    it('should convert testnet address URL from Tonscan to Tonviewer', () => {
      const input = `https://testnet.tonscan.org/address/${TEST_TON_ADDRESS}`;
      const expected = `https://testnet.tonviewer.com/${TEST_TON_ADDRESS}?address`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should convert testnet address URL from Tonviewer to Tonscan', () => {
      const input = `https://testnet.tonviewer.com/${TEST_TON_ADDRESS}?address`;
      const expected = `https://testnet.tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(expected);
    });

    it('should convert testnet transaction URL', () => {
      const input = `https://testnet.tonscan.org/tx/${TEST_TON_HASH}`;
      const expected = `https://testnet.tonviewer.com/transaction/${TEST_TON_HASH}`;
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });
  });

  describe('Explorer with the network in a URL parameter (actonscan)', () => {
    it('should add the network parameter when converting to actonscan', () => {
      expect(convertExplorerUrl(`https://tonscan.org/jetton/${TEST_TON_ADDRESS}`, 'actonscan'))
        .toBe(`https://actonscan.com/address/${TEST_TON_ADDRESS}?network=mainnet`);
      expect(convertExplorerUrl(`https://testnet.tonviewer.com/transaction/${TEST_TON_HASH}`, 'actonscan'))
        .toBe(`https://actonscan.com/tx/${TEST_TON_HASH}?network=testnet`);
    });

    it('should detect the network by the parameter when converting from actonscan', () => {
      expect(convertExplorerUrl(`https://actonscan.com/tx/${TEST_TON_HASH}?network=mainnet`, 'tonscan'))
        .toBe(`https://tonscan.org/tx/${TEST_TON_HASH}`);
      expect(convertExplorerUrl(`https://actonscan.com/tx/${TEST_TON_HASH}?network=testnet`, 'tonscan'))
        .toBe(`https://testnet.tonscan.org/tx/${TEST_TON_HASH}`);
    });

    it('should treat an actonscan URL without the network parameter as mainnet', () => {
      expect(convertExplorerUrl(`https://actonscan.com/address/${TEST_TON_ADDRESS}`, 'tonviewer'))
        .toBe(`https://tonviewer.com/${TEST_TON_ADDRESS}?address`);
    });

    it('should convert an actonscan address to the plain address page', () => {
      expect(convertExplorerUrl(`https://actonscan.com/address/${TEST_NFT_ADDRESS}?network=testnet`, 'tonscan'))
        .toBe(`https://testnet.tonscan.org/address/${TEST_NFT_ADDRESS}`);
    });

    it('should replace the network parameter in the fallback conversion', () => {
      expect(convertExplorerUrl('https://actonscan.com/blocks?network=testnet', 'tonscan'))
        .toBe('https://testnet.tonscan.org/blocks');
    });

    it('should keep the rest of the query and the fragment in the fallback conversion', () => {
      expect(convertExplorerUrl('https://testnet.tonscan.org/blocks?page=2', 'actonscan'))
        .toBe('https://actonscan.com/blocks?page=2&network=testnet');
      expect(convertExplorerUrl('https://tonscan.org/blocks#top', 'actonscan'))
        .toBe('https://actonscan.com/blocks?network=mainnet#top');
      expect(convertExplorerUrl('https://actonscan.com/blocks?network=testnet&page=2#top', 'tonscan'))
        .toBe('https://testnet.tonscan.org/blocks?page=2#top');
    });
  });

  describe('Explorer without message hashes (actonscan)', () => {
    it('should keep a transaction link that may hold a message hash when asked to', () => {
      expect(convertExplorerUrl(`https://tonscan.org/tx/${TEST_MESSAGE_HASH}`, 'actonscan', true)).toBeUndefined();
      expect(convertExplorerUrl(`https://tonscan.org/tx/${TEST_MESSAGE_HASH}`, 'tonviewer', true))
        .toBe(`https://tonviewer.com/transaction/${TEST_MESSAGE_HASH}`);
      expect(convertExplorerUrl(`https://tonscan.org/address/${TEST_TON_ADDRESS}`, 'actonscan', true))
        .toBe(`https://actonscan.com/address/${TEST_TON_ADDRESS}?network=mainnet`);
    });
  });

  describe('URLs with query strings and fragments', () => {
    it('should preserve query string when converting address URL', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}?tab=tokens`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      // Query string is not preserved in the converted URL (identifier extraction stops at ?)
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });

    it('should handle URLs with hash fragments', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}#section`;
      const expected = `https://tonviewer.com/${TEST_TON_ADDRESS}?address`;
      // Hash fragment is not preserved (identifier extraction stops at #)
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });
  });

  describe('Edge cases', () => {
    it('should return the same URL if already on target explorer', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBe(input);
    });

    it('should return undefined for non-explorer URLs', () => {
      expect(convertExplorerUrl('https://google.com', 'tonscan')).toBeUndefined();
      expect(convertExplorerUrl('https://example.com/path', 'tonviewer')).toBeUndefined();
    });

    it('should return undefined for invalid explorer ID', () => {
      const input = `https://tonscan.org/address/${TEST_TON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'nonexistent')).toBeUndefined();
    });

    it('should return undefined for cross-chain conversion attempts', () => {
      const tronUrl = `https://tronscan.org/#/address/${TEST_TRON_ADDRESS}`;
      expect(convertExplorerUrl(tronUrl, 'tonscan')).toBeUndefined();
    });

    it('should use fallback for URLs that do not match any pattern', () => {
      // Create a URL that starts with explorer base but doesn't match any pattern
      const input = 'https://tonscan.org/unknown/path';
      const expected = 'https://tonviewer.com/unknown/path';
      expect(convertExplorerUrl(input, 'tonviewer')).toBe(expected);
    });
  });

  describe('TRON explorer (single explorer, no conversion)', () => {
    it('should return the same URL for TRON explorer (only one explorer available)', () => {
      const input = `https://tronscan.org/#/address/${TEST_TRON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tronscan')).toBe(input);
    });

    it('should return undefined when trying to convert TRON to non-existent explorer', () => {
      const input = `https://tronscan.org/#/address/${TEST_TRON_ADDRESS}`;
      expect(convertExplorerUrl(input, 'tonscan')).toBeUndefined();
    });
  });
});

describe('explorer URLs of the selected explorer', () => {
  it('should use the base URL and parameter of the selected explorer', () => {
    const base64Hash = Buffer.from(TEST_TON_HASH, 'hex').toString('base64');

    expect(getExplorerAddressUrl('ton', TEST_TON_ADDRESS, false, 'tonviewer'))
      .toBe(`https://tonviewer.com/${TEST_TON_ADDRESS}?address`);
    expect(getExplorerAddressUrl('ton', TEST_TON_ADDRESS, true, 'actonscan'))
      .toBe(`https://actonscan.com/address/${TEST_TON_ADDRESS}?network=testnet`);
    expect(getExplorerTransactionUrl('ton', { traceId: base64Hash }, false, 'actonscan'))
      .toBe(`https://actonscan.com/tx/${TEST_TON_HASH}?network=mainnet`);
  });
});

describe('getExplorerTransactionUrl', () => {
  const messageHash = Buffer.from(TEST_MESSAGE_HASH, 'hex').toString('base64');
  const traceId = Buffer.from(TEST_TON_HASH, 'hex').toString('base64');

  it('links the trace id in every explorer when it is known', () => {
    expect(getExplorerTransactionUrl('ton', { hash: messageHash, traceId }, false, 'actonscan'))
      .toBe(`https://actonscan.com/tx/${TEST_TON_HASH}?network=mainnet`);
    expect(getExplorerTransactionUrl('ton', { hash: messageHash, traceId }, false, 'tonviewer'))
      .toBe(`https://tonviewer.com/transaction/${TEST_TON_HASH}`);
  });

  it('opens a hash without a trace id in an explorer that finds a trace by its message hash', () => {
    expect(getExplorerTransactionUrl('ton', { hash: messageHash }, false, 'tonviewer'))
      .toBe(`https://tonviewer.com/transaction/${TEST_MESSAGE_HASH}`);
    expect(getExplorerTransactionUrl('ton', { hash: messageHash }, false, 'actonscan'))
      .toBe(`https://tonscan.org/tx/${TEST_MESSAGE_HASH}`);
    expect(getExplorerTransactionUrl('ton', { hash: messageHash }, true, 'actonscan'))
      .toBe(`https://testnet.tonscan.org/tx/${TEST_MESSAGE_HASH}`);
  });

  it('keeps the selected explorer of a chain without message hashes', () => {
    expect(getExplorerTransactionUrl('ethereum', { hash: TEST_EVM_HASH }))
      .toBe(`https://etherscan.io/tx/${TEST_EVM_HASH}`);
  });
});

describe('isInIframeWhitelist', () => {
  it('accepts the whitelisted explorers', () => {
    expect(isInIframeWhitelist('https://tonscan.org')).toBe(true);
    expect(isInIframeWhitelist('https://actonscan.com/address/EQ123?network=mainnet')).toBe(true);
    expect(isInIframeWhitelist('https://tonscan.org/address/EQ123')).toBe(true);
    expect(isInIframeWhitelist('https://testnet.tonviewer.com/')).toBe(true);
  });

  it('accepts localhost on any port', () => {
    expect(isInIframeWhitelist('http://localhost:4321/index.html')).toBe(true);
  });

  // A whitelisted page gets the embedded dapp bridge (TonConnect connect/send), so a host that merely starts with
  // an allowed origin must not pass: `tonscan.org.evil.tld` is a domain the attacker owns.
  it('rejects a host that only starts with a whitelisted origin', () => {
    expect(isInIframeWhitelist('https://tonscan.org.evil.tld/steal')).toBe(false);
    expect(isInIframeWhitelist('https://tonviewer.com.evil.tld')).toBe(false);
    expect(isInIframeWhitelist('https://tonscan.org.evil.tld/tonscan.org')).toBe(false);
  });

  it('rejects a whitelisted host reached over a different scheme or as a subdomain', () => {
    expect(isInIframeWhitelist('http://tonscan.org')).toBe(false);
    expect(isInIframeWhitelist('https://evil.tonscan.org')).toBe(false);
    expect(isInIframeWhitelist('https://localhost.evil.tld')).toBe(false);
  });

  it('rejects a whitelisted origin smuggled into credentials or a path', () => {
    expect(isInIframeWhitelist('https://tonscan.org@evil.tld/')).toBe(false);
    expect(isInIframeWhitelist('https://evil.tld/https://tonscan.org')).toBe(false);
  });

  it('returns false on a malformed url instead of throwing', () => {
    expect(isInIframeWhitelist('not a url')).toBe(false);
    expect(isInIframeWhitelist('https://')).toBe(false);
    expect(isInIframeWhitelist('')).toBe(false);
  });

  // The bare origin carries an implicit default port, so the explicit form has to resolve to the same
  // whitelisted page, and localhost stays http-only because that is the single entry the list grants.
  it('normalizes the default port and keeps localhost http-only', () => {
    expect(isInIframeWhitelist('https://tonscan.org:443/address/EQ123')).toBe(true);
    expect(isInIframeWhitelist('https://localhost:4321')).toBe(false);
  });
});
