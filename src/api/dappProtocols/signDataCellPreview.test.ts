import { beginCell } from '@ton/core';
import * as tlbRuntime from '@ton-community/tlb-runtime';

import { buildSignDataCellPreview, shortenHash } from './signDataCellPreview';

const OFFCHAIN_ORDER_SCHEMA = [
  'offchain_order$_ salt:uint32 market_id:uint32',
  'maker_amount:(VarUInteger 16) taker_amount:(VarUInteger 16)',
  'is_buy:Bool is_yes:Bool creator_pub_key:uint256 = OffchainOrder;',
].join(' ');
const SCREENSHOT_OFFCHAIN_ORDER_CELL = [
  'te6ccgEBAQEANAAAY9J7IBAAAAABQDk4cAQF9e',
  'EAyTIsEobp1JyO1nctSTmgIXN/',
  'QvDIgAycefELP+McNwqg',
].join('');

function buildPreviewExpectingNoTlbParse(cell: string, schema: string) {
  const parseSpy = jest.spyOn(tlbRuntime, 'parseTLB');
  parseSpy.mockClear();

  try {
    const preview = buildSignDataCellPreview(cell, schema);
    expect(parseSpy).not.toHaveBeenCalled();
    return preview;
  } finally {
    parseSpy.mockRestore();
  }
}

function makeOffchainOrderCell() {
  return beginCell()
    .storeUint(643120343, 32)
    .storeUint(1, 32)
    .storeCoins(60000000n)
    .storeCoins(100000000n)
    .storeBit(true)
    .storeBit(true)
    .storeUint(
      BigInt('0x24e5b04a1ba752723b59dcb524e68255cdfd0bcc322003271e7c42cff8c70dc2'),
      256,
    )
    .endCell()
    .toBoc()
    .toString('base64');
}

describe('buildSignDataCellPreview', () => {
  it('parses TON Connect cell signData using its TL-B schema', () => {
    const preview = buildSignDataCellPreview(makeOffchainOrderCell(), OFFCHAIN_ORDER_SCHEMA);

    expect(preview.isParsed).toBe(true);
    expect(preview.error).toBeUndefined();
    expect(preview.title).toBe('OffchainOrder');
    expect(preview.bits).toBe(394);
    expect(preview.refs).toBe(0);
    expect(preview.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'kind', value: 'OffchainOrder', depth: 0 }),
      expect.objectContaining({ label: 'salt', value: '643120343 (0x26553cd7)', depth: 1 }),
      expect.objectContaining({ label: 'market_id', value: '1', depth: 1 }),
      expect.objectContaining({ label: 'maker_amount', value: '60000000 units', depth: 1 }),
      expect.objectContaining({ label: 'taker_amount', value: '100000000 units', depth: 1 }),
      expect.objectContaining({ label: 'is_buy', value: 'true', depth: 1 }),
      expect.objectContaining({ label: 'is_yes', value: 'true', depth: 1 }),
      expect.objectContaining({
        label: 'creator_pub_key',
        value: [
          '16689087232137192677571892554833841422276301465716194796607369818162095132098',
          '(0x24e5b04a1ba752723b59dcb524e68255cdfd0bcc322003271e7c42cff8c70dc2)',
        ].join(' '),
        depth: 1,
      }),
    ]));
  });

  it('parses the OffchainOrder cell from the TON Connect demo screenshot with neutral units display', () => {
    const preview = buildSignDataCellPreview(SCREENSHOT_OFFCHAIN_ORDER_CELL, OFFCHAIN_ORDER_SCHEMA);

    expect(preview.isParsed).toBe(true);
    expect(preview.error).toBeUndefined();
    expect(preview.title).toBe('OffchainOrder');
    expect(preview.bits).toBe(394);
    expect(preview.refs).toBe(0);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'kind', value: 'OffchainOrder', depth: 0 }),
      expect.objectContaining({ label: 'salt', value: '3531284496 (0xd27b2010)', depth: 1 }),
      expect.objectContaining({ label: 'market_id', value: '1', depth: 1 }),
      expect.objectContaining({ label: 'maker_amount', value: '60000000 units', depth: 1 }),
      expect.objectContaining({ label: 'taker_amount', value: '100000000 units', depth: 1 }),
      expect.objectContaining({ label: 'is_buy', value: 'true', depth: 1 }),
      expect.objectContaining({ label: 'is_yes', value: 'true', depth: 1 }),
      expect.objectContaining({
        label: 'creator_pub_key',
        value: [
          '16637848667258619532013976927312296627426286180673311114735064737351939972138',
          '(0x24c8b04a1ba752723b59dcb524e68085cdfd0bc322003271e7c42cff8c70dc2a)',
        ].join(' '),
        depth: 1,
      }),
    ]));
  });

  it('formats every declared VarUInteger 16 field as neutral units regardless of its name', () => {
    const cell = beginCell()
      .storeCoins(60000000n)
      .storeCoins(70000000n)
      .storeCoins(80000000n)
      .storeCoins(90000000n)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(
      cell,
      [
        'sample$_ amount:(VarUInteger 16)',
        'maker_amount:(VarUInteger 16)',
        'value:(VarUInteger 16)',
        'jetton_amount:(VarUInteger 16) = Sample;',
      ].join(' '),
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'amount', value: '60000000 units', depth: 1 }),
      expect.objectContaining({ label: 'maker_amount', value: '70000000 units', depth: 1 }),
      expect.objectContaining({ label: 'value', value: '80000000 units', depth: 1 }),
      expect.objectContaining({ label: 'jetton_amount', value: '90000000 units', depth: 1 }),
    ]));
  });

  it('uses declared VarUInteger 16 type for nested fields without changing other bigint formatting', () => {
    const cell = beginCell()
      .storeCoins(70n)
      .storeUint(512n, 64)
      .storeCoins(60n)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(
      cell,
      [
        'inner$_ nested_amount:(VarUInteger 16) fixed_amount:uint64 = Inner;',
        'root$_ child:Inner root_amount:(VarUInteger 16) = Root;',
      ].join(' '),
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'root_amount', value: '60 units', depth: 1 }),
      expect.objectContaining({ label: 'child', value: 'Inner', depth: 1 }),
      expect.objectContaining({ label: 'nested_amount', value: '70 units', depth: 2 }),
      expect.objectContaining({ label: 'fixed_amount', value: '512 (0x200)', depth: 2 }),
    ]));
  });

  it('uses tlb-runtime normalized field identities for reserved-name collisions', () => {
    const cell = beginCell()
      .storeUint(8n, 64)
      .storeCoins(9n)
      .storeUint(10n, 64)
      .storeCoins(11n)
      .storeUint(12n, 64)
      .storeCoins(13n)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(
      cell,
      [
        'root$_ var:uint64 var0:(VarUInteger 16)',
        'cell:uint64 cell0:(VarUInteger 16)',
        'slice:uint64 slice0:(VarUInteger 16) = Root;',
      ].join(' '),
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'var0', value: '8 (0x8)', depth: 1 }),
      expect.objectContaining({ label: 'var0_0', value: '9 units', depth: 1 }),
      expect.objectContaining({ label: '_cell', value: '10 (0xa)', depth: 1 }),
      expect.objectContaining({ label: '_cell0', value: '11 units', depth: 1 }),
      expect.objectContaining({ label: '_slice', value: '12 (0xc)', depth: 1 }),
      expect.objectContaining({ label: '_slice0', value: '13 units', depth: 1 }),
    ]));
  });

  it('uses normalized field metadata for nested multi-constructor values', () => {
    const cell = beginCell()
      .storeBit(true)
      .storeUint(8n, 64)
      .storeCoins(9n)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(
      cell,
      [
        'left$0 fixed:uint64 = Choice;',
        'right$1 var:uint64 var0:(VarUInteger 16) = Choice;',
        'root$_ choice:Choice = Root;',
      ].join(' '),
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'choice', value: 'Choice_right', depth: 1 }),
      expect.objectContaining({ label: 'var0', value: '8 (0x8)', depth: 2 }),
      expect.objectContaining({ label: 'var0_0', value: '9 units', depth: 2 }),
    ]));
  });

  it('applies units only to the exact unsigned VarUInteger 16 type', () => {
    const cell = beginCell()
      .storeVarUint(16n, 4)
      .storeVarUint(17n, 5)
      .storeVarInt(18n, 16)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(
      cell,
      [
        'root$_ exact:(VarUInteger 16)',
        'wider:(VarUInteger 17)',
        'signed:(VarInteger 16) = Root;',
      ].join(' '),
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'exact', value: '16 units', depth: 1 }),
      expect.objectContaining({ label: 'wider', value: '17 (0x11)', depth: 1 }),
      expect.objectContaining({ label: 'signed', value: '18 (0x12)', depth: 1 }),
    ]));
  });

  it('formats integer values independently of hash, digest, and flags-like field names', () => {
    const cell = beginCell()
      .storeUint(0x123n, 256)
      .storeUint(0x200n, 64)
      .storeUint(5, 8)
      .storeUint(512, 16)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(
      cell,
      'root$_ hash:uint256 digest:uint64 flags:uint8 flags_total:uint16 = Root;',
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'hash', value: '291 (0x123)', depth: 1 }),
      expect.objectContaining({ label: 'digest', value: '512 (0x200)', depth: 1 }),
      expect.objectContaining({ label: 'flags', value: '5', depth: 1 }),
      expect.objectContaining({ label: 'flags_total', value: '512 (0x200)', depth: 1 }),
    ]));
  });

  it('rejects TL-B parses that leave trailing root bits unaccounted for', () => {
    const cell = beginCell()
      .storeUint(0xab, 8)
      .storeUint(0xcd, 8)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(cell, 'root$_ x:uint8 = Root;');

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toBe('TL-B schema did not parse the complete root cell payload.');
  });

  it('rejects TL-B parses that leave trailing root refs unaccounted for', () => {
    const cell = beginCell()
      .storeUint(0xab, 8)
      .storeRef(beginCell().storeUint(0xcd, 8).endCell())
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(cell, 'root$_ x:uint8 = Root;');

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toBe('TL-B schema did not parse the complete root cell payload.');
  });

  it('uses the last declared TL-B type as the TON Connect root type instead of global tag discovery', () => {
    const cell = beginCell()
      .storeUint(0, 1)
      .storeUint(0x12, 8)
      .storeUint(0x34, 8)
      .endCell()
      .toBoc()
      .toString('base64');
    const schema = 'aux$0 x:uint8 = Aux; root$_ tag:Bool x:uint8 y:uint8 = Root;';
    const preview = buildSignDataCellPreview(cell, schema);

    expect(preview.isParsed).toBe(true);
    expect(preview.title).toBe('Root');
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'tag', value: 'false', depth: 1 }),
      expect.objectContaining({ label: 'x', value: '18', depth: 1 }),
      expect.objectContaining({ label: 'y', value: '52', depth: 1 }),
    ]));
  });

  it.each([
    ['line comment', 'aux$_ x:uint8 = Aux; // helper = Fake\nroot$_ x:uint8 = Root;'],
    ['block comment', 'aux$_ x:uint8 = Aux; /* helper = Fake; */ root$_ x:uint8 = Root;'],
    ['trailing block comment', 'aux$_ x:uint8 = Aux; root$_ x:uint8 = Root; /* = Aux; */'],
    ['trailing line comment', 'aux$_ x:uint8 = Aux; root$_ x:uint8 = Root; // = Aux;'],
    ['exact trailing comment probe', 'root$_ x:uint8 = Root; // = Fake;'],
  ])('derives the root from normalized runtime types with a %s', (_description, schema) => {
    const cell = beginCell().storeUint(7, 8).endCell().toBoc().toString('base64');
    const preview = buildSignDataCellPreview(cell, schema);

    expect(preview.isParsed).toBe(true);
    expect(preview.title).toBe('Root');
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'x', value: '7', depth: 1 }),
    ]));
  });

  it('falls back before TL-B parsing when schema length exceeds deterministic limits', () => {
    const oversizedSchema = `root$_ x:uint8 = Root;${' '.repeat(16 * 1024)}`;
    const preview = buildPreviewExpectingNoTlbParse(makeOffchainOrderCell(), oversizedSchema);

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toBe('TL-B schema exceeds preview limit (16384 chars).');
    expect(preview.fields[0]).toEqual(expect.objectContaining({ label: 'payload' }));
  });

  it('falls back before TL-B parsing when schema field count exceeds deterministic limits', () => {
    const oversizedSchema = `root$_ ${Array.from({ length: 257 }, (_, index) => `f${index}:uint1`).join(' ')} = Root;`;
    const preview = buildPreviewExpectingNoTlbParse(makeOffchainOrderCell(), oversizedSchema);

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toBe('TL-B schema exceeds preview field limit (256).');
    expect(preview.fields[0]).toEqual(expect.objectContaining({ label: 'payload' }));
  });

  it('does not reject harmless schemas based on their line count alone', () => {
    const schema = `${'\n'.repeat(600)}root$_ x:uint8 = Root;`;
    const cell = beginCell().storeUint(7, 8).endCell().toBoc().toString('base64');
    const preview = buildSignDataCellPreview(cell, schema);

    expect(preview.isParsed).toBe(true);
    expect(preview.title).toBe('Root');
  });

  it('caps array preview output without walking past the field limit', () => {
    const builder = beginCell();
    for (let index = 0; index < 101; index++) {
      builder.storeUint(index, 8);
    }
    const preview = buildSignDataCellPreview(
      builder.endCell().toBoc().toString('base64'),
      'root$_ values:(101 * uint8) = Root;',
    );

    expect(preview.isParsed).toBe(true);
    expect(preview.fields).toHaveLength(100);
    expect(preview.fields.at(-1)).toEqual(expect.objectContaining({ label: '[97]' }));
  });

  it('falls back before cell parsing or TL-B parsing when cell payload exceeds deterministic limits', () => {
    const oversizedCell = 'A'.repeat(90000);
    const preview = buildPreviewExpectingNoTlbParse(oversizedCell, 'root$_ x:uint8 = Root;');

    expect(preview.isParsed).toBe(false);
    expect(preview.bits).toBe(0);
    expect(preview.refs).toBe(0);
    expect(preview.hash).toBeUndefined();
    expect(preview.error).toBe('Cell payload exceeds preview limit (65536 bytes).');
    expect(preview.fields[0]).toEqual(expect.objectContaining({ label: 'payload', value: '90000 base64 chars' }));
  });

  it('extracts the root type from constrained TL-B declarations without treating constraints as results', () => {
    const cell = beginCell()
      .storeUint(7, 8)
      .storeUint(7, 8)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(cell, 'root$_ a:uint8 b:uint8 {a = b} = Root;');

    expect(preview.isParsed).toBe(true);
    expect(preview.title).toBe('Root');
    expect(preview.fields).toEqual(expect.arrayContaining([
      expect.objectContaining({ label: 'a', value: '7', depth: 1 }),
      expect.objectContaining({ label: 'b', value: '7', depth: 1 }),
    ]));
  });

  it('returns raw payload metadata when the TL-B schema cannot parse the cell', () => {
    const preview = buildSignDataCellPreview(makeOffchainOrderCell(), 'bad schema');

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toBe('Bad Schema');
    expect(preview.title).toBe('TON Cell');
    expect(preview.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(preview.fields).toEqual([
      expect.objectContaining({ label: 'payload', value: expect.stringMatching(/base64 chars$/) }),
    ]);
  });

  it('falls back clearly for documented standard types that tlb-runtime does not support yet', () => {
    const cell = beginCell()
      .storeUint(0, 32)
      .storeStringTail('Hello, TON!')
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(cell, 'message#_ text:string = Message;');

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toContain('Type string not found');
    expect(preview.fields[0]).toEqual(expect.objectContaining({ label: 'payload' }));
  });

  it('falls back clearly for unsupported standard combinators', () => {
    const cell = beginCell()
      .storeBit(true)
      .storeUint(7, 8)
      .endCell()
      .toBoc()
      .toString('base64');
    const preview = buildSignDataCellPreview(cell, 'msg$_ value:(Maybe uint8) = Msg;');

    expect(preview.isParsed).toBe(false);
    expect(preview.error).toContain('Type Maybe not found');
  });

  it('handles invalid base64 cell payloads gracefully', () => {
    const preview = buildSignDataCellPreview('not-a-cell', OFFCHAIN_ORDER_SCHEMA);

    expect(preview.isParsed).toBe(false);
    expect(preview.hash).toBeUndefined();
    expect(preview.bits).toBe(0);
    expect(preview.refs).toBe(0);
    expect(preview.error).toBeTruthy();
    expect(preview.fields[0]).toEqual(expect.objectContaining({ label: 'payload', value: '10 base64 chars' }));
  });
});

describe('shortenHash', () => {
  it('shortens long hashes for compact display', () => {
    expect(shortenHash('1234567890abcdef1234567890abcdef')).toBe('1234567890...7890abcdef');
  });
});
