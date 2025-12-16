import type { LangCode } from '../global/types';
import type { LangFn } from './langProvider';

import { formatEnumeration, processTemplateJsx } from './langProvider';

// Create a mock React element for testing
const createMockElement = (type: string, props: any = {}, children?: any) => ({
  type,
  props: { ...props, children },
  // eslint-disable-next-line no-null/no-null
  key: null,
  // eslint-disable-next-line no-null/no-null
  ref: null,
});

describe('processTemplateJsx', () => {
  describe('Processing of simple string values', () => {
    const stringTestCases = [{
      name: 'must replace the single token with a string',
      template: 'More about %app_name%',
      value: { app_name: 'MyTonWallet' },
      expected: ['More about MyTonWallet'],
    }, {
      name: 'must replace multiple tokens with strings',
      template: 'Transfer %amount% %symbol%',
      value: { amount: '100', symbol: 'TON' },
      expected: ['Transfer 100 TON'],
    }, {
      name: 'must replace the tokens with numbers',
      template: 'Import From %count% Secret Words',
      value: { count: 24 },
      expected: ['Import From 24 Secret Words'],
    }, {
      name: 'must handle recurring tokens',
      template: '%app_name% is secure. Use %app_name% safely.',
      value: { app_name: 'MyTonWallet' },
      expected: ['MyTonWallet is secure. Use MyTonWallet safely.'],
    }];

    stringTestCases.forEach(({ name, template, value, expected }) => {
      it(name, () => {
        const result = processTemplateJsx(template, value);
        expect(result).toEqual(expected);
      });
    });
  });

  describe('Teact component processing', () => {
    it('must insert a Teact component into the template', () => {
      const template = 'Swap %from% %icon% %to%';
      const mockIcon = createMockElement('i', { className: 'icon-chevron-right', 'aria-hidden': true });
      const value = {
        from: 'TON',
        icon: mockIcon,
        to: 'USDT',
      };

      const result = processTemplateJsx(template, value);

      expect(result).toHaveLength(3);
      expect(result[0]).toBe('Swap TON ');
      expect(result[1]).toBe(mockIcon);
      expect(result[2]).toBe(' USDT');
    });
  });

  describe('Markdown and line breaks processing', () => {
    const markdownTestCases = [{
      name: 'handles bold markdown text',
      template: 'Create **secure** wallet',
      expectedLength: 3,
      expectedFirstPart: 'Create ',
      expectedSecondType: 'object',
      expectedTag: 'b',
    }, {
      name: 'handles line breaks',
      template: 'Line 1\nLine 2',
      expectedLength: 3,
      expectedFirstPart: 'Line 1',
      expectedSecondType: 'object',
      expectedTag: 'br',
    }];

    markdownTestCases.forEach(({
      name,
      template,
      expectedLength,
      expectedFirstPart,
      expectedSecondType,
      expectedTag,
    }) => {
      it(name, () => {
        const result = processTemplateJsx(template, {});

        expect(result).toHaveLength(expectedLength);
        expect(result[0]).toBe(expectedFirstPart);
        expect(typeof result[1]).toBe(expectedSecondType);
        expect((result[1] as any).tag).toBe(expectedTag);
      });
    });

    it('handles markdown with tokens', () => {
      const template = '**%app_name%** is secure';
      const value = { app_name: 'MyTonWallet' };

      const result = processTemplateJsx(template, value);

      expect(result).toHaveLength(2);
      expect(typeof result[0]).toBe('object');
      expect((result[0] as any).tag).toBe('b');
      expect(typeof (result[0] as any).children[0]).toBe('object');
      expect((result[0] as any).children[0].value).toBe('MyTonWallet');
    });
  });

  describe('Basic cases', () => {
    const basicTestCases = [{
      name: 'handles empty template',
      template: '',
      value: {},
      expected: [],
    }, {
      name: 'handles template without tokens',
      template: 'Simple text without tokens',
      value: {},
      expected: ['Simple text without tokens'],
    }, {
      name: 'leaves undefined tokens untouched',
      template: 'Hello %name% and %unknown%',
      value: { name: 'World' },
      expected: ['Hello World and %unknown%'],
    }];

    basicTestCases.forEach(({ name, template, value, expected }) => {
      it(name, () => {
        const result = processTemplateJsx(template, value);
        expect(result).toEqual(expected);
      });
    });
  });

  describe('Translation file examples', () => {
    const translationTestCases = [{
      name: 'handles Russian "More about %app_name%" string',
      template: 'Подробнее о %app_name%',
      value: { app_name: 'MyTonWallet' },
      expected: ['Подробнее о MyTonWallet'],
    }, {
      name: 'handles fee string',
      template: 'Комиссия %fee%',
      value: { fee: '0.01 TON' },
      expected: ['Комиссия 0.01 TON'],
    }];

    translationTestCases.forEach(({ name, template, value, expected }) => {
      it(name, () => {
        const result = processTemplateJsx(template, value);
        expect(result).toEqual(expected);
      });
    });
  });

  describe('formatEnumeration', () => {
    it('returns empty array for empty array', () => {
      expect(formatEnumeration(mockLangFn(), [], 'and')).toBe('');
    });

    it('returns single item as string', () => {
      expect(formatEnumeration(mockLangFn(), ['A'], 'and')).toBe('A');
    });

    it('joins two items with "or"', () => {
      expect(formatEnumeration(mockLangFn(), ['A', 'B'], 'or')).toBe('A 又は B');
    });

    it('joins three items with "and"', () => {
      expect(formatEnumeration(mockLangFn(), ['A', 'B', 'C'], 'and')).toBe('A、B そして C');
    });

    it('joins many items', () => {
      expect(formatEnumeration(mockLangFn(), ['A', 'B', 'C', 'D', 'E', 'F'], 'and')).toBe('A、B、C、D、E そして F');
    });

    it('joins Teact nodes', () => {
      const nodeA = createMockElement('span', {}, 'A');
      const nodeB = createMockElement('span', {}, 'B');
      const nodeC = createMockElement('span', {}, 'C');
      const result = formatEnumeration(mockLangFn(), [nodeA, nodeB, nodeC], 'and');
      expect(result).toEqual([nodeA, '、', nodeB, ' そして ', nodeC]);
    });

    it('joins mixed items', () => {
      const nodeA = createMockElement('span', {}, 'A');
      const nodeB = 'B';
      const result = formatEnumeration(mockLangFn(), [nodeA, nodeB], 'or');
      expect(result).toEqual([nodeA, ' 又は ', nodeB]);
    });

    describe('`preferCompact` option', () => {
      function getResult(code: LangCode) {
        return formatEnumeration(mockLangFn(code), ['A', 'B', 'C'], 'or', true);
      }

      it('trims spaces when Chinese', () => {
        expect(getResult('zh-Hans')).toBe('A、B又はC');
      });

      it('doesn\'t trim spaces when not Chinese', () => {
        expect(getResult('pl')).toBe('A、B 又は C');
      });
    });

    function mockLangFn(code?: LangCode) {
      const langFn: LangFn = (key: string) => {
        if (key === '$joining_comma') return '、';
        if (key === '$joining_and') return ' そして ';
        if (key === '$joining_or') return ' 又は ';
        return key;
      };
      langFn.code = code;
      return langFn;
    }
  });
});
