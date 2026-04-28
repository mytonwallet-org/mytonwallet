import { ContentTab } from '../../types';

import { unique } from '../../../util/iteratees';
import { addActionHandler, setGlobal } from '../../index';
import { updateCurrentAccountSettings, updateCurrentAccountState, updateSettings } from '../../reducers';
import { selectCurrentAccountSettings } from '../../selectors';

addActionHandler('showTokenActivity', (global, actions, { slug, returnTab }) => {
  if (returnTab !== undefined) {
    setGlobal(updateCurrentAccountState(global, { activityReturnContentTab: returnTab }));
  }
  actions.selectToken({ slug }, { forceOnHeavyAnimation: true });
  actions.setActiveContentTab({ tab: ContentTab.Activity });
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

addActionHandler('setWalletTokensLimit', (global, actions, { limit }) => {
  return updateCurrentAccountSettings(global, { walletTokensLimit: limit });
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
