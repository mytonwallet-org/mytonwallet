import type { LangFn } from '../../../../../hooks/useLang';
import type { TabWithProperties } from '../../../../ui/TabList';

import { IS_LEDGER_SUPPORTED } from '../../../../../util/windowEnvironment';
import { AccountTab, TAB_TITLES } from '../constants';

// Build tabs array based on environment
export function buildTabs(isTestnet: boolean, lang: LangFn): TabWithProperties<AccountTab>[] {
  const result: TabWithProperties<AccountTab>[] = [
    { id: AccountTab.All, title: lang(TAB_TITLES[AccountTab.All]) },
    { id: AccountTab.My, title: lang(TAB_TITLES[AccountTab.My]) },
  ];

  if (IS_LEDGER_SUPPORTED && !isTestnet) {
    result.push({ id: AccountTab.Ledger, title: lang(TAB_TITLES[AccountTab.Ledger]) });
  }

  result.push({ id: AccountTab.View, title: lang(TAB_TITLES[AccountTab.View]) });

  return result;
}

// Get current tab index from tabs array
export function getCurrentTabIndex(tabs: TabWithProperties<AccountTab>[], activeTab: AccountTab): number {
  const idx = tabs.findIndex((tab) => tab.id === activeTab);
  return idx >= 0 ? idx : 0;
}
