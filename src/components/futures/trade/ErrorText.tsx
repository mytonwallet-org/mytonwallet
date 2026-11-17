import React, { memo } from '../../../lib/teact/teact';

import type { PerpsErrorDetails } from '../../../global/types';

import { getPerpsErrorText } from '../helpers/formatPerps';

import useLang from '../../../hooks/useLang';

import styles from './TradeModal.module.scss';

interface OwnProps {
  error: string;
  details?: PerpsErrorDetails;
}

function ErrorText({ error, details }: OwnProps) {
  const lang = useLang();

  return <p className={styles.errorText}>{getPerpsErrorText(lang, error, details)}</p>;
}

export default memo(ErrorText);
