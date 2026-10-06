import { hexToBytes } from '../../common/utils';
import { zcashWirePrevoutHash } from './signZcash';

describe('zcashWirePrevoutHash', () => {
  it('reverses Blockbook display txid to wire prevout hash', () => {
    const display = hexToBytes('c19d2dd68f4297fc7f77a79e207d104bf0fa7831b73676f24ecaba485fcb754e');
    const wire = zcashWirePrevoutHash(display);

    expect(Buffer.from(wire).toString('hex')).toBe(
      '4e75cb5f48baca4ef27636b73178faf04b107d209ea7777ffc97428fd62d9dc1',
    );
  });
});
