import React, { memo } from '../../lib/teact/teact';

import type { ApiSwapActivity } from '../../api/types';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

interface OwnProps {
  cex?: ApiSwapActivity['cex'];
  isHold?: boolean;
  classNames: {
    description: string;
    descriptionBold: string;
    supportContact: string;
  };
}

function CexSupportText({ cex, isHold, classNames }: OwnProps) {
  const lang = useLang();
  const supportDetails = getCexSupportDetails(cex);

  if (!supportDetails) return undefined;

  const { providerName, supportUrl, supportEmail } = supportDetails;
  const supportLabel = lang('$swap_cex_provider_support', { provider: providerName });
  const support = supportUrl ? (
    <a
      href={supportUrl}
      target="_blank"
      rel="noreferrer"
      className={classNames.descriptionBold}
    >
      {supportLabel}
    </a>
  ) : (
    <span className={classNames.descriptionBold}>{supportLabel}</span>
  );
  const langKey = isHold ? '$swap_cex_hold_support' : '$swap_cex_support';

  return (
    <>
      <span className={classNames.description}>
        {lang(langKey, { support })}
      </span>
      {supportEmail && (
        <>
          <span className={classNames.description}>{lang('Email')}</span>
          <a
            href={`mailto:${supportEmail}`}
            className={buildClassName(classNames.descriptionBold, classNames.supportContact)}
          >
            {supportEmail}
          </a>
        </>
      )}
    </>
  );
}

function getCexSupportDetails(cex?: ApiSwapActivity['cex']) {
  if (cex?.providerName && (cex.supportUrl || cex.supportEmail)) {
    return {
      providerName: cex.providerName,
      supportUrl: cex.supportUrl,
      supportEmail: cex.supportEmail,
    };
  }

  return undefined;
}

export default memo(CexSupportText);
