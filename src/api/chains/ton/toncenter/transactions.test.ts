import type { AddressBook, Transaction } from './types';

import { calculateOutgoingTransactionFee, parseRawTransaction } from './transactions';

const nil = undefined as never;

const walletRaw = `0:${'1'.repeat(64)}`;
const firstRecipientRaw = `0:${'2'.repeat(64)}`;
const secondRecipientRaw = `0:${'3'.repeat(64)}`;

const addressBook: AddressBook = {
  [walletRaw]: { user_friendly: 'UQ-wallet', domain: nil },
  [firstRecipientRaw]: { user_friendly: 'UQ-first', domain: nil },
  [secondRecipientRaw]: { user_friendly: 'UQ-second', domain: nil },
};

function makeMessage(destination: string, value: string, fwdFee: string) {
  return {
    hash: `hash-${destination}`,
    source: walletRaw,
    destination,
    value,
    fwd_fee: fwdFee,
    hash_norm: undefined,
    value_extra_currencies: {},
    ihr_fee: nil,
    created_lt: nil,
    created_at: nil,
    opcode: nil,
    ihr_disabled: nil,
    bounce: nil,
    bounced: nil,
    import_fee: nil,
    message_content: { hash: '', body: '' },
  };
}

function makeOutgoingTransaction(): Transaction {
  return {
    account: walletRaw,
    hash: 'tx-hash',
    lt: '1',
    now: 1,
    mc_block_seqno: 1,
    trace_id: 'trace-id',
    prev_trans_hash: 'prev',
    prev_trans_lt: '0',
    orig_status: 'active',
    end_status: 'active',
    total_fees: '1000',
    total_fees_extra_currencies: {},
    description: {
      type: 'generic',
      aborted: false,
      destroyed: false,
      credit_first: false,
      storage_ph: { storage_fees_collected: '0', status_change: 'unchanged' },
      compute_ph: {
        skipped: false,
        success: true,
        msg_state_used: false,
        account_activated: false,
        gas_fees: '0',
        gas_used: '0',
        gas_limit: '0',
        gas_credit: '0',
        mode: 0,
        exit_code: 0,
        vm_steps: 0,
        vm_init_state_hash: '',
        vm_final_state_hash: '',
      },
      action: {
        success: true,
        valid: true,
        no_funds: false,
        status_change: 'unchanged',
        total_fwd_fees: '150',
        total_action_fees: '50',
        result_code: 0,
        tot_actions: 2,
        spec_actions: 0,
        skipped_actions: 0,
        msgs_created: 2,
        action_list_hash: '',
        tot_msg_size: { cells: '0', bits: '0' },
      },
    },
    block_ref: { workchain: 0, shard: '', seqno: 1 },
    in_msg: {
      ...makeMessage(walletRaw, '0', '0'),
      source: nil,
      destination: walletRaw,
    },
    init_state: nil,
    out_msgs: [
      makeMessage(firstRecipientRaw, '10', '40'),
      makeMessage(secondRecipientRaw, '20', '60'),
    ],
    account_state_before: {
      hash: '',
      balance: '0',
      extra_currencies: {},
      account_status: 'active',
      frozen_hash: nil,
      data_hash: '',
      code_hash: '',
    },
    account_state_after: {
      hash: '',
      balance: '0',
      extra_currencies: {},
      account_status: 'active',
      frozen_hash: nil,
      data_hash: '',
      code_hash: '',
    },
    emulated: true,
  };
}

describe('TON transaction fee parsing', () => {
  it('includes outgoing forward fees in parsed outgoing W5 transaction fees', () => {
    const rawTx = makeOutgoingTransaction();

    expect(calculateOutgoingTransactionFee(rawTx)).toBe(1100n);
    expect(parseRawTransaction('mainnet', rawTx, addressBook).map(({ fee }) => fee)).toEqual([540n, 560n]);
  });
});
