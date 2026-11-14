import type { AgentActionKind, AgentHintPoolResponseV2 } from './protocol/types';

import compatibilityFixture from '../../../tests/fixtures/agentV2/client-wire-compatibility.v1.json';
import { selectAgentV2StarterHints } from './starterHints';

const POOL = compatibilityFixture.fixtures
  .find(({ schema }) => schema === 'AgentHintPoolResponseV2')!.values[0] as AgentHintPoolResponseV2;
const ALL_ACTIONS: AgentActionKind[] = ['send', 'receive', 'stake', 'swap'];
const RANDOM_VALUES = [0, 0.2, 0.4, 0.6, 0.8, 0.99];

describe('selectAgentV2StarterHints', () => {
  it('picks one hint per group in the order of the groups', () => {
    expect(selectAgentV2StarterHints(POOL.items, ALL_ACTIONS, 'funded', () => 0)).toEqual([
      { id: 'wallet.assets', group: 'wallet' },
      { id: 'market.today', group: 'market' },
      { id: 'staking.yield', group: 'learn' },
      { id: 'action.swap', group: 'action' },
    ]);
    expect(selectAgentV2StarterHints(POOL.items, ALL_ACTIONS, 'funded', () => 0.99).map(({ id }) => id)).toEqual([
      'wallet.last_transfer', 'market.price', 'learn.multisend', 'receive.tokens',
    ]);
    expect([0.24, 0.25, 0.74, 0.75].map((value) => (
      selectAgentV2StarterHints(POOL.items, ALL_ACTIONS, 'funded', () => value)[0].id
    ))).toEqual(['wallet.assets', 'wallet.total', 'wallet.spending', 'wallet.last_transfer']);
    expect(selectAgentV2StarterHints([
      { id: 'wallet.assets', group: 'wallet', walletState: 'funded' },
      { id: 'market.today', group: 'market' },
      { id: 'wallet.fund', group: 'wallet', walletState: 'empty' },
    ], ALL_ACTIONS, 'empty', () => 0).map(({ group }) => group)).toEqual(['wallet', 'market']);
    expect(selectAgentV2StarterHints([
      { id: 'action.send', group: 'action', requiredActions: ['send'] },
      { id: 'market.today', group: 'market' },
      { id: 'learn.security', group: 'learn' },
      { id: 'wallet.assets', group: 'wallet', walletState: 'funded' },
    ], ALL_ACTIONS, 'funded', () => 0).map(({ group }) => group)).toEqual(['action', 'market', 'learn', 'wallet']);
  });

  it('skips the hints that need an action the account lacks, and a group left without hints', () => {
    const hints = RANDOM_VALUES.flatMap((value) => selectAgentV2StarterHints(POOL.items, [], 'funded', () => value));

    expect(new Set(hints.map(({ group }) => group))).toEqual(new Set(['wallet', 'market', 'learn']));
    expect(selectAgentV2StarterHints(POOL.items, ['receive'], 'funded', () => 0)
      .find(({ group }) => group === 'action')).toEqual({ id: 'receive.tokens', group: 'action' });
    expect(selectAgentV2StarterHints(
      [{ id: 'action.swap', group: 'action', requiredActions: ['send', 'swap'] }], ['send'], 'funded', () => 0,
    )).toEqual([]);
  });

  it('matches the wallet hints to the wallet state', () => {
    function selectWalletIds(walletState?: 'funded' | 'empty') {
      return new Set(RANDOM_VALUES.flatMap((value) => (
        selectAgentV2StarterHints(POOL.items, ALL_ACTIONS, walletState, () => value)
      )).filter(({ group }) => group === 'wallet').map(({ id }) => id));
    }

    expect(selectWalletIds('empty')).toEqual(new Set(['wallet.fund']));
    expect(selectWalletIds('funded')).toEqual(
      new Set(['wallet.assets', 'wallet.total', 'wallet.spending', 'wallet.last_transfer']),
    );
    expect(selectWalletIds(undefined)).toEqual(new Set());
    expect(selectAgentV2StarterHints(POOL.items, ALL_ACTIONS, undefined, () => 0).map(({ id }) => id)).toEqual([
      'market.today', 'staking.yield', 'action.swap',
    ]);
  });
});
