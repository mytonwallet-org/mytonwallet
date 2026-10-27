import React, { memo } from '../../lib/teact/teact';

import type { ApiInfoBannerPromotion } from '../../api/types';

import { SENSITIVE_DATA_MASK } from '../../config';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';

import styles from './InfoBanner.module.scss';

interface OwnProps {
  banner: Pick<ApiInfoBannerPromotion, 'id' | 'infoBanner'>;
  isLoading?: boolean;
  isSensitiveDataHidden?: boolean;
  className?: string;
  onActionClick: (id: string) => void;
  onClose: (id: string) => void;
}

const PLACEHOLDER_SIGN_REGEX = /^%|%$/g;
// `%amount%` carries a balance of the user, such as the amount staked with another provider, so hidden balances mask it
const BALANCE_PLACEHOLDER = 'amount';

function InfoBanner({
  banner,
  isLoading,
  isSensitiveDataHidden,
  className,
  onActionClick,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const { id, infoBanner: { title, description, textValues, actionButton } } = banner;
  const values = buildLangValues(textValues, isSensitiveDataHidden);

  const handleActionClick = useLastCallback(() => {
    onActionClick(id);
  });

  const handleClose = useLastCallback(() => {
    onClose(id);
  });

  return (
    <div
      className={buildClassName(styles.root, !isLoading && styles.rootActive, className)}
      aria-busy={isLoading || undefined}
      onClick={!isLoading ? handleActionClick : undefined}
    >
      <p className={styles.title}>{lang(title, values)}</p>
      <div className={styles.body}>
        <p className={styles.description}>{lang(description, values)}</p>
        {/* The click bubbles up to the card */}
        <Button isSimple isLoading={isLoading} className={styles.button}>
          {lang(actionButton.title)}
        </Button>
      </div>
      <Button
        isSimple
        isRound
        isDisabled={isLoading}
        shouldStopPropagation
        className={styles.close}
        ariaLabel={lang('Close')}
        onClick={handleClose}
      >
        <i className="icon-close" aria-hidden />
      </Button>
    </div>
  );
}

export default memo(InfoBanner);

// The SDK keeps the `%` signs of the placeholders in the `textValues` keys, while `lang` expects bare names.
// The values object is passed even when empty, so `lang` renders the Markdown of the text.
function buildLangValues(textValues?: Record<string, string>, isSensitiveDataHidden?: boolean) {
  const values: Record<string, string> = {};

  for (const [key, value] of Object.entries(textValues ?? {})) {
    const name = key.replace(PLACEHOLDER_SIGN_REGEX, '');
    values[name] = isSensitiveDataHidden && name === BALANCE_PLACEHOLDER ? SENSITIVE_DATA_MASK : value;
  }

  return values;
}
