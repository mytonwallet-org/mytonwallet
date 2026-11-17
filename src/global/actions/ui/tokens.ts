import { ContentTab } from '../../types';

import {
  getIsChainVisible,
  getNormalizedManualOrder,
  setChainDisplayMode,
  setChainVisibility,
  setManualChainOrder,
} from '../../../util/chainDisplay';
import { unique } from '../../../util/iteratees';
import { addActionHandler, setGlobal } from '../../index';
import {
  updateCurrentAccountSettings,
  updateCurrentAccountState,
  updateCurrentChainDisplayConfiguration,
  updateSettings,
} from '../../reducers';
import {
  selectCurrentAccountChainDisplay,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsMarketTokenOpen,
} from '../../selectors';

addActionHandler('showTokenActivity', (global, actions, { slug, returnTab }) => {
  // A token screen opened from Market switches its token and leaves the wallet tab alone
  if (returnTab === undefined && selectIsMarketTokenOpen(global)) {
    actions.selectToken({ slug }, { forceOnHeavyAnimation: true });
    return;
  }

  const { activeContentTab, currentTokenSlug } = selectCurrentAccountState(global) ?? {};
  // A closed market keeps its token selected until its reset runs, and that token has no wallet place to keep
  const isWalletTokenOpen = Boolean(currentTokenSlug) && currentTokenSlug !== global.marketTokenSlug;

  // A token opened from another token keeps the place the first one returns to
  if (returnTab !== undefined || !isWalletTokenOpen) {
    setGlobal(updateCurrentAccountState(global, { activityReturnContentTab: returnTab ?? activeContentTab }));
  }
  actions.selectToken({ slug }, { forceOnHeavyAnimation: true });
  actions.setActiveContentTab({ tab: ContentTab.Activity });
});

addActionHandler('closeTokenActivity', (global, actions) => {
  const { activeContentTab, activityReturnContentTab } = selectCurrentAccountState(global) ?? {};
  const isMarketTokenOpen = selectIsMarketTokenOpen(global);

  actions.selectToken({ slug: undefined }, { forceOnHeavyAnimation: true });

  // A token opened from Market leaves the wallet tab alone, so there is nothing to restore
  if (!isMarketTokenOpen && activeContentTab === ContentTab.Activity) {
    actions.setActiveContentTab({ tab: activityReturnContentTab ?? ContentTab.Overview });
  }
});

addActionHandler('toggleTokensWithNoCost', (global, actions, { isEnabled }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};

  global = updateCurrentAccountSettings(global, {
    ...accountSettings,
    alwaysShownSlugs: [],
    alwaysHiddenSlugs: [],
  });

  return updateSettings(global, { areTokensWithNoCostHidden: isEnabled });
});

addActionHandler('pinToken', (global, actions, { slug }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  const { pinnedSlugs = [] } = accountSettings;

  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    pinnedSlugs: unique([slug, ...pinnedSlugs]),
  });
});

addActionHandler('unpinToken', (global, actions, { slug }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  const { pinnedSlugs = [] } = accountSettings;

  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    pinnedSlugs: pinnedSlugs.filter((s) => s !== slug),
  });
});

addActionHandler('toggleTokenVisibility', (global, actions, { slug, shouldShow }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  const { alwaysShownSlugs = [], alwaysHiddenSlugs = [] } = accountSettings;
  const alwaysShownSlugsSet = new Set(alwaysShownSlugs);
  const alwaysHiddenSlugsSet = new Set(alwaysHiddenSlugs);

  if (shouldShow) {
    alwaysHiddenSlugsSet.delete(slug);
    alwaysShownSlugsSet.add(slug);
  } else {
    alwaysShownSlugsSet.delete(slug);
    alwaysHiddenSlugsSet.add(slug);
  }

  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    alwaysHiddenSlugs: Array.from(alwaysHiddenSlugsSet),
    alwaysShownSlugs: Array.from(alwaysShownSlugsSet),
  });
});

addActionHandler('toggleChainVisibility', (global, actions, { chain, shouldShow }) => {
  const chainDisplay = selectCurrentAccountChainDisplay(global);
  if (!chainDisplay) return undefined;

  const { config, orderedChains, defaultVisibleChains } = chainDisplay;
  let newConfig = setChainVisibility(
    setChainDisplayMode(config, 'manual'),
    chain,
    shouldShow,
    defaultVisibleChains.has(chain),
  );

  // `orderedChains` keeps the hidden chains after the shown ones, so a chain switched back on takes the last place
  // among the shown ones instead of jumping to wherever it used to be
  if (shouldShow) {
    newConfig = setManualChainOrder(newConfig, orderedChains, defaultVisibleChains);
  }

  return updateCurrentChainDisplayConfiguration(global, newConfig);
});

addActionHandler('setChainDisplayMode', (global, actions, { displayMode }) => {
  const chainDisplay = selectCurrentAccountChainDisplay(global);
  if (!chainDisplay) return undefined;

  const {
    config, defaultOrder, orderedChains, defaultVisibleChains,
  } = chainDisplay;
  if (config.displayMode === displayMode) return undefined;

  // The manual mode needs an order to start from. An order saved earlier is reused, otherwise the order currently
  // on the screen is written down - so the rows stay where they are at the moment the switch is flipped.
  const capturedOrder = displayMode === 'manual'
    ? (config.manualOrder?.length
      ? getNormalizedManualOrder(config, defaultOrder, defaultVisibleChains)
      : orderedChains.filter((chain) => getIsChainVisible(config, chain, defaultVisibleChains)))
    : undefined;
  const newConfig = setChainDisplayMode(config, displayMode, capturedOrder);

  return updateCurrentChainDisplayConfiguration(global, newConfig);
});

addActionHandler('updateChainDisplayOrder', (global, actions, { orderedChains }) => {
  const chainDisplay = selectCurrentAccountChainDisplay(global);
  if (!chainDisplay) return undefined;

  const { config, defaultVisibleChains } = chainDisplay;
  const newConfig = setChainDisplayMode(config, 'manual');

  return updateCurrentChainDisplayConfiguration(
    global,
    setManualChainOrder(newConfig, orderedChains, defaultVisibleChains),
  );
});

addActionHandler('setAreAssetsHidden', (global, actions, { isHidden }) => {
  return updateCurrentAccountSettings(global, {
    areAssetsHidden: isHidden ? true : undefined,
  });
});

addActionHandler('setAreCollectiblesHidden', (global, actions, { isHidden }) => {
  return updateCurrentAccountSettings(global, {
    areCollectiblesHidden: isHidden ? true : undefined,
  });
});

addActionHandler('deleteToken', (global, actions, { slug }) => {
  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  return updateCurrentAccountSettings(global, {
    ...accountSettings,
    pinnedSlugs: accountSettings.pinnedSlugs?.filter((s) => s !== slug),
    alwaysHiddenSlugs: accountSettings.alwaysHiddenSlugs?.filter((s) => s !== slug),
    alwaysShownSlugs: accountSettings.alwaysShownSlugs?.filter((s) => s !== slug),
    deletedSlugs: unique([...accountSettings.deletedSlugs ?? [], slug]),
    importedSlugs: accountSettings.importedSlugs?.filter((s) => s !== slug),
  });
});
