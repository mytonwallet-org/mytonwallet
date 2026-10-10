import type { ApiChain } from '../types';
import type {
  ActionSendRecipientV1,
  AgentApiChain,
  AgentAssetRefV2,
  AgentPersistedActionV2,
  AgentPersistedNavigationActionV3,
  AgentV2LiveAction,
} from './protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2HostAsset,
  AgentV2HostContextSnapshot,
  AgentV2ResolvedAction,
} from './types';
import type { AgentV2WalletSession } from './walletSession';

import { getChainConfig, getIsSupportedChain } from '../../util/chain';
import { getAgentV2ActionAvailability } from './actionAvailability';
import { BoundedRetainedRegistry } from './boundedRetainedRegistry';
import {
  safeWalletQueryAccountLabel,
  safeWalletQueryAssetSymbol,
  safeWalletQueryIdentifierDisplay,
} from './walletQueryOutput';

const ACTION_MAX_ENTRIES = 512;
const ACTION_TTL_MS = 24 * 60 * 60_000;
const LIVE_ACTION_NAMESPACE = 'live';
const PERSISTED_ACTION_NAMESPACE = 'persisted';

interface ScopedAction<T> {
  messageId: string;
  threadId: string;
  action: T;
}

export class AgentV2ActionResolver {
  private readonly actions: BoundedRetainedRegistry;

  constructor(private readonly session: AgentV2WalletSession, now: () => number = Date.now) {
    this.actions = new BoundedRetainedRegistry(ACTION_MAX_ENTRIES, ACTION_TTL_MS, now);
  }

  resolveAction(messageId: string, actionId: string): AgentV2ResolvedAction {
    const key = actionKey(messageId, actionId);
    const live = this.actions.get<ScopedAction<AgentV2LiveAction>>(LIVE_ACTION_NAMESPACE, key);
    const persisted = this.actions.get<ScopedAction<AgentPersistedActionV2>>(PERSISTED_ACTION_NAMESPACE, key);
    if (live) return this.resolveLiveAction(live);
    if (persisted) return this.resolvePersistedAction(persisted);
    return { kind: 'inactive' };
  }

  getActionPresentation(messageId: string, actionId: string): AgentV2ActionPresentation {
    const key = actionKey(messageId, actionId);
    const live = this.actions.get<ScopedAction<AgentV2LiveAction>>(
      LIVE_ACTION_NAMESPACE,
      key,
    );
    const persisted = this.actions.get<ScopedAction<AgentPersistedActionV2>>(
      PERSISTED_ACTION_NAMESPACE,
      key,
    );
    const scoped = live ?? persisted;
    if (!scoped) return { kind: 'inactive' };
    return this.buildActionPresentation(scoped.action);
  }

  registerAction(threadId: string, messageId: string, action: AgentV2LiveAction) {
    this.actions.set(
      LIVE_ACTION_NAMESPACE,
      actionKey(messageId, action.id),
      { threadId, messageId, action } satisfies ScopedAction<AgentV2LiveAction>,
      { threadId },
    );
  }

  registerPersistedAction(threadId: string, messageId: string, action: AgentPersistedActionV2) {
    this.actions.set(
      PERSISTED_ACTION_NAMESPACE,
      actionKey(messageId, action.id),
      { threadId, messageId, action } satisfies ScopedAction<AgentPersistedActionV2>,
      { threadId },
    );
  }

  private buildActionPresentation(
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) {
    if (action.kind === 'send' && action.effect === 'open_send') {
      const binding = this.resolveSendFormBinding(action);
      if (!binding) return { kind: 'inactive' as const };
      return {
        kind: 'send',
        status: 'active',
        network: binding.network,
        accountLabel: safeWalletQueryAccountLabel(binding.active),
        ...(binding.destination ? { recipient: binding.destination.presentation } : {}),
        ...(action.amount && binding.metadata ? {
          amount: { value: action.amount, symbol: safeWalletQueryAssetSymbol(binding.metadata) },
        } : {}),
        feeStatus: 'calculated_in_wallet',
        warningCodes: [],
      } satisfies AgentV2ActionPresentation;
    }
    return { kind: 'inactive' as const };
  }

  private resolveLiveAction(scoped: ScopedAction<AgentV2LiveAction>): AgentV2ResolvedAction {
    const { action } = scoped;
    if (!this.session.snapshot().host?.uiCapabilities?.supportedActions.includes(action.kind)) {
      return { kind: 'inactive' };
    }
    switch (action.kind) {
      case 'send':
        return this.resolveSendFormAction(action);
      case 'swap':
        return this.resolveSwapAction(action);
      case 'receive':
        return this.resolveLiveReceiveAction(action);
      case 'stake':
        return this.resolveLiveStakeAction(action);
      case 'openDapp':
        return resolveNavigationAction(action);
      default:
        return assertUnreachableAction(action);
    }
  }

  private resolvePersistedAction(
    scoped: ScopedAction<AgentPersistedActionV2>,
  ): AgentV2ResolvedAction {
    const { action } = scoped;
    if (!this.session.snapshot().host?.uiCapabilities?.supportedActions.includes(action.kind)) {
      return { kind: 'inactive' };
    }
    switch (action.kind) {
      case 'send':
        return { kind: 'inactive' };
      case 'swap':
        return this.resolveSwapAction(action);
      case 'receive':
        return this.resolveReceiveAction(
          'schemaVersion' in action && action.schemaVersion === 3
            ? action.targetNetwork
            : undefined,
        );
      case 'stake':
        return this.resolveStakeAction(action);
      case 'openDapp':
        return 'schemaVersion' in action && action.schemaVersion === 3
          ? resolveNavigationAction(action)
          : { kind: 'inactive' };
      default:
        return assertUnreachableAction(action);
    }
  }

  // Receive opens for the current wallet on the bound network, independently of unrelated query revisions.
  private resolveLiveReceiveAction(action: Extract<AgentV2LiveAction, { kind: 'receive' }>) {
    const snapshot = this.session.snapshot();
    if (
      action.contextBinding.sessionId !== snapshot.sessionId
      || action.contextBinding.activeNetwork !== snapshot.host?.activeNetwork
    ) return { kind: 'inactive' } as const;
    const targetNetwork = 'schemaVersion' in action && action.schemaVersion === 3
      ? action.targetNetwork
      : undefined;
    return this.resolveReceiveAction(targetNetwork);
  }

  // Stake opens for the current wallet; its own asset chain can differ from the currently selected network.
  private resolveLiveStakeAction(action: Extract<AgentV2LiveAction, { kind: 'stake' }>) {
    if (action.contextBinding.sessionId !== this.session.snapshot().sessionId) return { kind: 'inactive' } as const;
    return this.resolveStakeAction(action);
  }

  private resolveStakeAction(
    action: Extract<AgentV2LiveAction | AgentPersistedActionV2, { kind: 'stake' }>,
  ): AgentV2ResolvedAction {
    const host = this.session.snapshot().host;
    const activeAccount = host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
    if (!getAgentV2ActionAvailability(host).canOpenStaking
      || !activeAccount?.chains.includes(action.asset.chain)) return { kind: 'inactive' };
    const amount = action.amount;
    if (amount?.kind === 'exact') {
      const fractionLength = amount.value.split('.')[1]?.length ?? 0;
      if (action.asset.decimals === undefined
        || fractionLength > action.asset.decimals
        || !/[1-9]/u.test(amount.value)) {
        return { kind: 'inactive' };
      }
    }
    return {
      kind: 'openStaking',
      productId: action.productId,
      tokenSlug: action.asset.slug,
      ...(amount ? { amount } : {}),
    };
  }

  private resolveReceiveAction(targetNetwork?: AgentApiChain): AgentV2ResolvedAction {
    const snapshot = this.session.snapshot();
    const host = snapshot.host;
    const activeAccount = host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
    if (!getAgentV2ActionAvailability(host).canOpenReceive
      || !host?.activeNetwork || !activeAccount) return { kind: 'inactive' };
    const resolvedNetwork = targetNetwork ?? host.activeNetwork;
    if (targetNetwork && targetNetwork !== host.activeNetwork && activeAccount.isViewOnly) {
      return { kind: 'inactive' };
    }
    if (!activeAccount.chains.includes(resolvedNetwork)) return { kind: 'inactive' };
    return { kind: 'openReceive', chain: resolvedNetwork };
  }

  private resolveSwapAction(
    action: Extract<AgentV2LiveAction | AgentPersistedActionV2, { kind: 'swap' }>,
  ): AgentV2ResolvedAction {
    const snapshot = this.session.snapshot();
    const host = snapshot.host;
    const active = host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
    if (!getAgentV2ActionAvailability(host).canPrepareSwap || !active) {
      return { kind: 'inactive' };
    }
    if (action.amount?.side === 'source' && !action.sourceAsset) return { kind: 'inactive' };
    if (action.amount?.side === 'destination' && (
      !action.sourceAsset || !action.destinationAsset
      || action.sourceAsset.chain !== action.destinationAsset.chain
      || !getIsSupportedChain(action.sourceAsset.chain)
      || !getChainConfig(action.sourceAsset.chain).canSwapByBuyAmount
    )) return { kind: 'inactive' };
    if ('contextBinding' in action && action.contextBinding.sessionId !== snapshot.sessionId) {
      return { kind: 'inactive' };
    }
    return {
      kind: 'openSwap',
      url: action.url,
      ...(action.sourceAsset ? { tokenInSlug: action.sourceAsset.slug } : {}),
      ...(action.destinationAsset ? { tokenOutSlug: action.destinationAsset.slug } : {}),
      ...(action.amount ? { amount: action.amount.value, amountSide: action.amount.side } : {}),
    };
  }

  clear(threadId?: string) {
    if (!threadId) {
      this.actions.clear();
      return;
    }
    this.actions.deleteWhere((entry) => entry.threadId === threadId);
  }

  private resolveSendFormAction(
    action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }>,
  ): AgentV2ResolvedAction {
    const binding = this.resolveSendFormBinding(action);
    if (!binding) return { kind: 'inactive' };
    if (!binding.asset && !binding.destination && !action.comment) return { kind: 'sendForm', url: 'mtw://send' };
    // Without `token` the Send form chooses the asset itself
    const query = new URLSearchParams(binding.asset ? { token: binding.asset.slug } : {});
    if (binding.amountAtomic !== undefined) query.set('amount', binding.amountAtomic);
    if (action.comment) query.set('text', action.comment);
    const recipient = encodeURIComponent(binding.destination?.raw ?? '').replaceAll('%3A', ':');
    // Native deeplink parsers read `+` literally, so spaces are percent-encoded
    const search = query.toString().replaceAll('+', '%20');
    return {
      kind: 'sendForm',
      url: `mtw://send/${binding.network}:${recipient}${search ? `?${search}` : ''}`,
      // The host fills the maximum itself, as its Max button does, since it knows the network fee
      ...(action.isMaxAmount ? { isMaxAmount: true as const } : {}),
    };
  }

  private resolveSendFormBinding(
    action: Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }>,
  ) {
    const snapshot = this.session.snapshot();
    const host = snapshot.host;
    const active = getActiveAccount(host);
    // The form opens for the current wallet, which checks the asset and balance again before signing.
    // A view-only wallet cannot send, so the button waits until the user switches to one that can.
    if (
      !host
      || !active
      || active.isViewOnly
      || !getAgentV2ActionAvailability(host).canOpenSend
      || action.contextBinding.sessionId !== snapshot.sessionId
    ) return undefined;
    if (!action.asset) {
      if (!host.activeNetwork || action.contextBinding.activeNetwork !== host.activeNetwork
        || !active.chains.includes(host.activeNetwork) || action.amount !== undefined
        || action.isMaxAmount) return undefined;
      const network = requireApiChain(host.activeNetwork);
      try {
        const destination = action.recipient
          ? resolveSendDestination(this.session, action.recipient, network)
          : undefined;
        return { active, destination, network, asset: undefined, metadata: undefined, amountAtomic: undefined };
      } catch {
        return undefined;
      }
    }
    if (!active.chains.includes(action.asset.chain)) return undefined;
    const asset = action.asset;
    // Holdings are not required here: the wallet decides whether the asset can be sent.
    // The asset must still be one the wallet knows, so the form opens exactly that token.
    const metadata = active.holdings.find((holding) => isSameAsset(holding.asset, asset))?.asset
      ?? host.assetCatalog?.find((candidate) => isSameAsset(candidate, asset));
    if (!metadata) return undefined;
    try {
      const network = requireApiChain(asset.chain);
      const destination = action.recipient
        ? resolveSendDestination(this.session, action.recipient, network)
        : undefined;
      const amountAtomic = action.amount ? decimalToAtomic(action.amount, metadata.decimals).toString() : undefined;
      return { active, asset, metadata, destination, network, amountAtomic };
    } catch {
      return undefined;
    }
  }
}

function actionKey(messageId: string, actionId: string) {
  return `${messageId}:${actionId}`;
}

type ResolvableNavigationAction =
  | Extract<AgentV2LiveAction, { kind: 'openDapp' }>
  | AgentPersistedNavigationActionV3;

function resolveNavigationAction(action: ResolvableNavigationAction): AgentV2ResolvedAction {
  return action.url.trim().length > 0 && action.url.length <= 2_048
    ? { kind: 'openDapp', url: action.url }
    : { kind: 'inactive' };
}

function assertUnreachableAction(value: never): never {
  throw new Error(`Unexpected Agent V2 action: ${String(value)}`);
}

function isSameAsset(candidate: AgentV2HostAsset, asset: AgentAssetRefV2) {
  return candidate.slug === asset.slug
    && candidate.chain === asset.chain
    && (candidate.tokenAddress ?? undefined) === (asset.tokenAddress ?? undefined);
}

function getActiveAccount(host?: AgentV2HostContextSnapshot) {
  return host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
}

function isDecimal(value: string) {
  return /^(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(value);
}

function decimalToAtomic(value: string, decimals: number) {
  if (!isDecimal(value) || !Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    throw new Error('The transfer amount is invalid.');
  }
  const [whole, fraction = ''] = value.split('.');
  if (fraction.length > decimals) {
    throw new Error('The transfer amount precision is invalid.');
  }
  return BigInt(`${whole}${fraction.padEnd(decimals, '0')}`);
}

function resolveSendDestination(
  session: AgentV2WalletSession,
  recipient: ActionSendRecipientV1,
  network: ApiChain,
) {
  if (recipient.kind === 'savedAddress') {
    const snapshot = session.snapshot();
    const raw = snapshot.addresses.get(recipient.addressRef);
    const profileAccounts = snapshot.host?.accounts.filter(({ state }) => state !== 'deleted') ?? [];
    const entry = profileAccounts.flatMap((account) => (account.savedAddresses ?? []).filter((candidate) => (
      session.resolveSavedAddressRefs(account.accountId, candidate.id)?.addressRef === recipient.addressRef
    )))[0] ?? snapshot.host?.savedAddresses.find((candidate) => (
      snapshot.addressRefs.get(`saved:${candidate.id}`) === recipient.addressRef
    ));
    const ownAccount = profileAccounts.find((account) => (
      session.resolveWalletAddressRefs(account.accountId, network)?.addressRef === recipient.addressRef
    ));
    if (!raw || (!entry && !ownAccount) || (entry && entry.chain !== network)) {
      throw new Error('The saved recipient is invalid.');
    }
    const label = ownAccount
      ? safeWalletQueryAccountLabel(ownAccount)
      : safeWalletQueryIdentifierDisplay(entry?.name, raw, 80);
    return {
      raw,
      presentation: {
        kind: 'savedAddress' as const,
        label,
      },
    };
  }
  if (recipient.chain !== network) {
    throw new Error('The recipient network is invalid.');
  }
  const raw = recipient.kind === 'address' ? recipient.address : recipient.domain;
  if (!raw.trim()) throw new Error('The recipient is invalid.');
  return {
    raw,
    presentation: { kind: recipient.kind === 'address' ? 'external' as const : 'domain' as const },
  };
}

function requireApiChain(value?: string): ApiChain {
  if (!getIsSupportedChain(value)) {
    throw new Error('The active network is not supported.');
  }
  return value;
}
