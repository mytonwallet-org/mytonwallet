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

  describe('card variant (default)', () => {
    describe('single-chain account', () => {
      test('TON chain with address', () => {
        const result = formatAccountAddresses(singleChainTonAccount);

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check address format (3 chars left, 4 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('UQA···U1V2');
      });

      test('TON chain with domain', () => {
        const result = formatAccountAddresses(singleChainTonDomainAccount);

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check domain format (maxLength=8 for card variant)
        // 'mywalletverylong.ton' (20 chars) -> 'm···.ton' (8 chars)
        const text = getTextContent(result);
        expect(text).toBe('m···.ton');
        expect(text).not.toContain('UQA');
      });

      test('TRON chain with address', () => {
        const result = formatAccountAddresses(singleChainTronAccount);

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-tron');

        // Check address format (3 chars left, 4 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('TR7···Lj6t');
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

        // Check address format for multichain (0 chars left, 3 chars right for addresses)
        const text = getTextContent(result);
        expect(text).toContain('···1V2');
        expect(text).toContain('···j6t');

        // Check space separator for card variant
        expect(text).toMatch(/···1V2\s+···j6t/);
      });

      test('mixed: one with domain, one with address', () => {
        const result = formatAccountAddresses(multiChainDomainAccount);

        // Check domain format for TON (maxLength=8 for card variant)
        // 'wallet.ton' (10 chars) -> 'w···.ton' (8 chars)
        const text = getTextContent(result);
        expect(text).toContain('w');
        expect(text).toContain('···');
        expect(text).toContain('.ton');

        // Check address format for TRON (0 chars left, 3 chars right)
        expect(text).toContain('···j6t');
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

  describe('list variant', () => {
    describe('single-chain account', () => {
      test('TON chain with address', () => {
        const result = formatAccountAddresses(singleChainTonAccount, 'list');

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check address format (6 chars left, 6 chars right)
        const text = getTextContent(result);
        expect(text).toEqual('UQA1B2···T0U1V2');
      });

      test('TON chain with domain', () => {
        const result = formatAccountAddresses(singleChainTonDomainAccount, 'list');

        // Check icon class
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(1);
        expect(icons[0].props.className).toBe('icon-chain-ton');

        // Check domain format (maxLength=12 for list variant)
        // 'mywalletverylong.ton' (20 chars) -> 'mywal···.ton' (12 chars)
        const text = getTextContent(result);
        expect(text).toContain('mywal');
        expect(text).toContain('···');
        expect(text).toContain('.ton');
        expect(text).not.toContain('UQA');
      });

      test('TRON chain with address', () => {
        const result = formatAccountAddresses(singleChainTronAccount, 'list');

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
        const result = formatAccountAddresses(multiChainAccount, 'list');

        // Check both icons
        const icons = findElementsByTag(result, 'i');
        expect(icons).toHaveLength(2);
        expect(icons[0].props.className).toBe('icon-chain-ton');
        expect(icons[1].props.className).toBe('icon-chain-tron');

        // Check address format for multichain (0 chars left, 4 chars right for addresses)
        const text = getTextContent(result);
        expect(text).toContain('···U1V2');
        expect(text).toContain('···Lj6t');

        // Check comma separator
        expect(text).toContain(', ');
      });

      test('mixed: one with domain, one with address', () => {
        const result = formatAccountAddresses(multiChainDomainAccount, 'list');

        // Check domain format for TON (4 chars left, 4 chars right)
        // Note: 'wallet.ton' is 10 chars, which is less than 4+4+3=11, so it won't be shortened
        const text = getTextContent(result);
        expect(text).toContain('wallet.ton');

        // Check address format for TRON (0 chars left, 4 chars right)
        expect(text).toContain('···Lj6t');
      });
    });

    describe('short addresses/domains', () => {
      test('short address that should not be truncated', () => {
        const result = formatAccountAddresses(shortSingleChainTonAccount, 'list');

        // Short address should be displayed as is (no truncation)
        const text = getTextContent(result);
        expect(text).toContain('SHORT');
        expect(text).not.toContain('···');
      });

      test('short domain in single-chain', () => {
        const result = formatAccountAddresses(shortSingleChainTonDomainAccount, 'list');

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
