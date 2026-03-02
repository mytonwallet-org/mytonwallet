import { VirtualType } from '../lib/teact/teact';

import type { Account } from '../global/types';

import { formatAccountAddresses } from './formatAccountAddress';

const singleChainTonAccount: Account['byChain'] = {
  ton: {
    address: 'UQA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0U1V2',
  },
};
const singleChainTonDomainAccount: Account['byChain'] = {
  ton: {
    address: 'UQA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0U1V2',
    domain: 'mywalletverylong.ton',
  },
};
const singleChainTronAccount: Account['byChain'] = {
  tron: {
    address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  },
};
const multiChainAccount: Account['byChain'] = {
  ton: {
    address: 'UQA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0U1V2',
  },
  tron: {
    address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  },
};
const multiChainDomainAccount: Account['byChain'] = {
  ton: {
    address: 'UQA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0U1V2',
    domain: 'wallet.ton',
  },
  tron: {
    address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  },
};
const shortSingleChainTonAccount: Account['byChain'] = {
  ton: {
    address: 'SHORT',
  },
};
const shortSingleChainTonDomainAccount: Account['byChain'] = {
  ton: {
    address: 'UQA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0U1V2',
    domain: 'ab.ton',
  },
};

describe('formatAccountAddresses', () => {
  describe('empty or invalid input', () => {
    test('empty byChain object', () => {
      const byChain: Account['byChain'] = {};
      const result = formatAccountAddresses(byChain);

      expect(result).toBeUndefined();
    });
  });

  describe('medium variant (default)', () => {
    describe('single-chain account', () => {
      test('TON chain with address', () => {
        const result = formatAccountAddresses(singleChainTonAccount);

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check address format (6 chars left, 6 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('UQA1B2···T0U1V2');
      });

      test('TON chain with domain', () => {
        const result = formatAccountAddresses(singleChainTonDomainAccount);

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check domain format (maxLength=12)
        const text = getTextContent(result);
        expect(text).toBe('mywal···.ton');
        expect(text).not.toContain('UQA');
      });

      test('TRON chain with address', () => {
        const result = formatAccountAddresses(singleChainTronAccount);

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-tron');

        // Check address format (6 chars left, 6 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('TR7NHq···gjLj6t');
      });
    });

    describe('multi-chain account', () => {
      test('TON and TRON with addresses only', () => {
        const result = formatAccountAddresses(multiChainAccount);

        // Check both icons
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(2);
        expect(icons[0].props.className).toBe('icon-chain-ton');
        expect(icons[1].props.className).toBe('icon-chain-tron');

        // Check address format for multichain (0 chars left, 6 chars right for addresses)
        const text = getTextContent(result);
        expect(text).toContain('···T0U1V2');
        expect(text).toContain('···gjLj6t');

        // Check comma separator for medium variant
        expect(text).toContain(', ');
      });

      test('mixed: one with domain, one with address', () => {
        const result = formatAccountAddresses(multiChainDomainAccount);

        // Check domain format for TON (maxLength=12)
        const text = getTextContent(result);
        expect(text).toContain('wallet.ton');

        // Check address format for TRON (0 chars left, 6 chars right)
        expect(text).toContain('···gjLj6t');

        // Check comma separator
        expect(text).toContain(', ');
      });
    });

    describe('short addresses/domains', () => {
      test('short address that should not be truncated', () => {
        const result = formatAccountAddresses(shortSingleChainTonAccount);

        // Short address should be displayed as is (no truncation)
        const text = getTextContent(result);
        expect(text).toContain('SHORT');
        expect(text).not.toContain('···');
      });

      test('short domain in single-chain', () => {
        const result = formatAccountAddresses(shortSingleChainTonDomainAccount);

        // Short domain should be displayed as is
        const text = getTextContent(result);
        expect(text).toContain('ab.ton');
        expect(text).not.toContain('···');
      });
    });
  });

  describe('small variant', () => {
    describe('single-chain account', () => {
      test('TON chain with address', () => {
        const result = formatAccountAddresses(singleChainTonAccount, 'small');

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check address format (0 chars left, 4 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('···U1V2');
      });

      test('TON chain with domain', () => {
        const result = formatAccountAddresses(singleChainTonDomainAccount, 'small');

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check domain format (maxLength=6)
        const text = getTextContent(result);
        expect(text).toBe('m···.ton');
        expect(text).not.toContain('UQA');
      });

      test('TRON chain with address', () => {
        const result = formatAccountAddresses(singleChainTronAccount, 'small');

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-tron');

        // Check address format (0 chars left, 4 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('···Lj6t');
      });
    });

    describe('multi-chain account', () => {
      test('TON and TRON with addresses only', () => {
        const result = formatAccountAddresses(multiChainAccount, 'small');

        // Check both icons are present
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(2);
        expect(icons[0].props.className).toBe('icon-chain-ton');
        expect(icons[1].props.className).toBe('icon-chain-tron');

        const text = getTextContent(result);

        // Only the first chain (TON) shows address text; TRON is icon-only
        expect(text).toContain('···U1V2');
        expect(text).not.toContain('···Lj6t');

        // Check space separator for small variant
        expect(text).toMatch(/···U1V2\s+/);
      });

      test('mixed: one with domain, one with address', () => {
        const result = formatAccountAddresses(multiChainDomainAccount, 'small');

        // Only the first chain (TON) shows domain text; TRON is icon-only
        const text = getTextContent(result);
        expect(text).toContain('w···.ton');
        expect(text).not.toContain('Lj6t');
      });
    });

    describe('short addresses/domains', () => {
      test('short address that should not be truncated', () => {
        const result = formatAccountAddresses(shortSingleChainTonAccount, 'small');

        // Short address should be displayed as is (no truncation)
        const text = getTextContent(result);
        expect(text).toContain('SHORT');
        expect(text).not.toContain('···');
      });

      test('short domain in single-chain', () => {
        const result = formatAccountAddresses(shortSingleChainTonDomainAccount, 'small');

        // Short domain should be displayed as is
        const text = getTextContent(result);
        expect(text).toContain('ab.ton');
        expect(text).not.toContain('···');
      });
    });
  });
});

/**
 * Helper function to extract text content from Teact elements
 */
function getTextContent(element: TeactJsx): string {
  if (typeof element === 'string') {
    return element;
  }

  if (!element) {
    return '';
  }

  if (element.type === VirtualType.Text) {
    return element.value || '';
  }

  // Handle children
  if (element.children) {
    if (Array.isArray(element.children)) {
      return element.children.map(getTextContent).join('');
    }
    return getTextContent(element.children);
  }

  return '';
}

/**
 * Helper function to find all elements with specific tag name
 */
function findElementsByTag(element: any, tagName: string): any[] {
  const results: any[] = [];

  if (!element) {
    return results;
  }

  if (element.type === VirtualType.Tag && element.tag === tagName) {
    results.push(element);
  }

  // Recursively search in children
  if (element.children) {
    const children = Array.isArray(element.children)
      ? element.children
      : [element.children];

    children.forEach((child: any) => {
      results.push(...findElementsByTag(child, tagName));
    });
  }

  return results;
}
