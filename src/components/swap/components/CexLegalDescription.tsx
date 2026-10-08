import React, { memo } from '../../../lib/teact/teact';

import useLang from '../../../hooks/useLang';

interface OwnProps {
  providerName: string;
  termsOfUseUrl?: string;
  privacyPolicyUrl?: string;
  amlKycPolicyUrl?: string;
  className?: string;
}

/** The legal note of a cross-chain exchange provider. Rendered empty unless both mandatory documents are known */
function CexLegalDescription({
  providerName,
  termsOfUseUrl,
  privacyPolicyUrl,
  amlKycPolicyUrl,
  className,
}: OwnProps) {
  const lang = useLang();

  if (!termsOfUseUrl || !privacyPolicyUrl) {
    return undefined;
  }

  const terms = (
    <a href={termsOfUseUrl} target="_blank" rel="noreferrer">
      {lang('$swap_cex_terms_of_use')}
    </a>
  );
  const policy = (
    <a href={privacyPolicyUrl} target="_blank" rel="noreferrer">
      {lang('$swap_cex_privacy_policy')}
    </a>
  );
  const aml = amlKycPolicyUrl ? (
    <a href={amlKycPolicyUrl} target="_blank" rel="noreferrer">
      {lang('$swap_cex_aml_kyc_policy_with_provider', { provider: providerName })}
    </a>
  ) : undefined;

  return (
    <span className={className}>
      {aml
        ? lang('$swap_cex_legal_message_with_aml', { terms, policy, aml })
        : lang('$swap_cex_legal_message', { terms, policy })}
    </span>
  );
}

export default memo(CexLegalDescription);
