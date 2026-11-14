import React, { memo } from '../../lib/teact/teact';

import { APP_PRIVACY_POLICY_URL, APP_TERMS_OF_USE_URL } from '../../config';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import getTestId from '../../util/getTestId';

import useLang from '../../hooks/useLang';

import styles from './AuthLegalNotice.module.scss';

interface OwnProps {
  className?: string;
}

function AuthLegalNotice({ className }: OwnProps) {
  const lang = useLang();

  return (
    <p className={buildClassName(styles.root, className)} data-testid={getTestId('intro_legal_notice')}>
      {lang('By continuing, you agree to our %terms% and %privacy%.', {
        terms: (
          <a href={APP_TERMS_OF_USE_URL} target="_blank" rel="noopener noreferrer">
            {renderText(lang('$auth_terms_of_use'))}
          </a>
        ),
        privacy: (
          <a href={APP_PRIVACY_POLICY_URL} target="_blank" rel="noopener noreferrer">
            {lang('$auth_privacy_policy')}
          </a>
        ),
      })}
    </p>
  );
}

export default memo(AuthLegalNotice);
