import { useEffect } from '../lib/teact/teact';

import useFlag from './useFlag';
import useModalTransitionKeys from './useModalTransitionKeys';

export enum AccountSwitcherScreen {
  Main = 0,
  Selector = 1,
}

export default function useAccountSwitcherScreen(isOpen?: boolean, currentAccountId?: string) {
  const [isSelectorOpen, openSelector, closeSelector] = useFlag();

  const activeKey = isSelectorOpen ? AccountSwitcherScreen.Selector : AccountSwitcherScreen.Main;

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(activeKey, Boolean(isOpen));

  useEffect(() => {
    if (!isOpen) closeSelector();
  }, [isOpen]);

  // The main content sticks to the account it was mounted with (`stickToFirst`), so leave the
  // selector only after the account actually changes and the main slide remounts with it
  useEffect(closeSelector, [closeSelector, currentAccountId]);

  return {
    renderingKey,
    nextKey,
    updateNextKey,
    isSelectorOpen,
    openSelector,
    closeSelector,
  };
}
