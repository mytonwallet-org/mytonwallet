import React, { memo } from '../../lib/teact/teact';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './ScrollToBottomButton.module.scss';

interface OwnProps {
  isVisible: boolean;
  onClick: NoneToVoidFunction;
}

function ScrollToBottomButton({ isVisible, onClick }: OwnProps) {
  const lang = useLang();
  const { ref, shouldRender } = useShowTransition<HTMLButtonElement>({
    isOpen: isVisible,
    withShouldRender: true,
  });

  if (!shouldRender) return undefined;

  return (
    <button
      ref={ref}
      type="button"
      className={styles.button}
      aria-label={lang('Scroll To Bottom')}
      onClick={onClick}
    >
      <i className="icon-chevron-down-alt" aria-hidden />
    </button>
  );
}

export default memo(ScrollToBottomButton);
