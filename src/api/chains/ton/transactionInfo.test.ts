import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import { OpCode as MfaOpCode } from './contracts/MfaExtension';
import { makeMockTransactionActivity } from '../../../../tests/mocks';
import { parseActionsToActivities } from './toncenter/actions';
import { fetchTraceByIdOrHash } from './toncenter/traces';
import { fetchTransactionById } from './transactionInfo';

jest.mock('../../common/addresses', () => ({
  getNftSuperCollectionsByCollectionAddress: jest.fn().mockResolvedValue({}),
}));
jest.mock('./toncenter/actions', () => ({
  parseActionsToActivities: jest.fn(),
}));
jest.mock('./toncenter/traces', () => ({
  fetchTraceByIdOrHash: jest.fn(),
}));

const WALLET = { raw: '0:2539', userFriendly: 'UQ-wallet' };
const EXTENSION = { raw: '0:9E8A', userFriendly: 'EQ-extension' };
const RELAYER = { raw: '0:1111', userFriendly: 'UQ-relayer' };
const CONTRACT = { raw: '0:52D7', userFriendly: 'EQ-contract' };
const JETTON_WALLET = { raw: '0:0C1A', userFriendly: 'EQ-jetton-wallet' };

const ADDRESS_BOOK = Object.fromEntries(
  [WALLET, EXTENSION, RELAYER, CONTRACT, JETTON_WALLET].map(({ raw, userFriendly }) => (
    [raw, { user_friendly: userFriendly, domain: undefined }]
  )),
);

const OPTIONS = { network: 'mainnet', walletAddress: '', txId: 'trace-id' } as const;

describe('fetchTransactionById', () => {
  it('parses the activities for the wallet that received the external message', async () => {
    const walletCall = makeActivity(WALLET, CONTRACT, 'callContract');
    const contractTransfer = makeActivity(CONTRACT, JETTON_WALLET);
    mockTrace({ root: WALLET, inOpCode: WalletContractV5R1.OpCodes.auth_signed_external }, [
      contractTransfer, walletCall,
    ]);

    const activities = await fetchTransactionById(OPTIONS);

    expect(parseActionsToActivities).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      walletAddress: WALLET.userFriendly,
    }));
    expect(activities).toEqual([walletCall]);
  });

  it('parses the activities for the wallet the MFA extension makes act', async () => {
    const extensionCall = makeActivity(EXTENSION, WALLET, undefined, true);
    const transfer = makeActivity(WALLET, CONTRACT);
    const deploy = makeActivity(JETTON_WALLET, CONTRACT, 'contractDeploy');
    mockTrace({
      root: EXTENSION,
      inOpCode: MfaOpCode.SEND_ACTIONS,
      outMessage: { destination: WALLET.raw, opcode: WalletContractV5R1.OpCodes.auth_extension },
    }, [extensionCall, transfer, deploy]);

    const activities = await fetchTransactionById(OPTIONS);

    expect(parseActionsToActivities).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      walletAddress: WALLET.userFriendly,
    }));
    expect(activities).toEqual([extensionCall, transfer]);
  });

  it('parses the activities for the wallet a gasless relayer makes act', async () => {
    const transfer = makeActivity(WALLET, CONTRACT);
    const relayerCall = makeActivity(RELAYER, WALLET, undefined, true);
    mockTrace({
      root: RELAYER,
      inOpCode: WalletContractV5R1.OpCodes.auth_signed_external,
      outMessage: { destination: WALLET.raw, opcode: WalletContractV5R1.OpCodes.auth_signed_internal },
    }, [relayerCall, transfer]);

    await fetchTransactionById(OPTIONS);

    expect(parseActionsToActivities).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      walletAddress: WALLET.userFriendly,
    }));
  });

  it('keeps all activities when the wallet is given', async () => {
    const walletCall = makeActivity(WALLET, CONTRACT, 'callContract');
    const contractTransfer = makeActivity(CONTRACT, JETTON_WALLET);
    mockTrace({ root: WALLET, inOpCode: WalletContractV5R1.OpCodes.auth_signed_external }, [
      contractTransfer, walletCall,
    ]);

    const activities = await fetchTransactionById({ ...OPTIONS, walletAddress: WALLET.userFriendly });

    expect(activities).toEqual([contractTransfer, walletCall]);
  });
});

function makeActivity(
  from: typeof WALLET,
  to: typeof WALLET,
  type?: 'callContract' | 'contractDeploy',
  isIncoming = false,
) {
  return makeMockTransactionActivity({
    fromAddress: from.userFriendly,
    toAddress: to.userFriendly,
    type,
    isIncoming,
    shouldLoadDetails: false,
  });
}

function mockTrace(
  root: { root: typeof WALLET; inOpCode: number; outMessage?: { destination: string; opcode: number } },
  activities: ReturnType<typeof makeActivity>[],
) {
  const toHex = (opCode: number) => `0x${opCode.toString(16)}`;

  (fetchTraceByIdOrHash as jest.Mock).mockResolvedValue({
    trace: {
      actions: [{}],
      trace: { tx_hash: 'root-hash', children: [] },
      transactions: {
        'root-hash': {
          account: root.root.raw,
          in_msg: { opcode: toHex(root.inOpCode) },
          out_msgs: root.outMessage
            ? [{ destination: root.outMessage.destination, opcode: toHex(root.outMessage.opcode) }]
            : [],
        },
      },
    },
    addressBook: ADDRESS_BOOK,
    metadata: {},
  });
  (parseActionsToActivities as jest.Mock).mockReturnValue(activities);
}
