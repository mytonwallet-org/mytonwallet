import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import type { OidcProvider } from '../hooks/useOidcProviders';
import type { ApiJwtCheck } from '../types';

import { DEBUG } from '../../config';
import {
  PUSH_APPLE_OAUTH_CLIENT_ID,
  PUSH_FACEBOOK_OAUTH_CLIENT_ID,
  PUSH_GOOGLE_OAUTH_CLIENT_ID,
  PUSH_MICROSOFT_OAUTH_CLIENT_ID,
} from '../config';
import buildClassName from '../../util/buildClassName';
import { bufferFromBigInt, hexFromArrayBuffer } from '../../util/casting';
import { calcAddressSha256HeadBase64 } from '../util/addressEncoders';
import { parseJwt } from '../util/jwt/jwt';

import useLang from '../../hooks/useLang';
import { PROVIDERS, useOidcProviders } from '../hooks/useOidcProviders';

import styles from './Oidc.module.scss';

type OwnProps = {
  check: ApiJwtCheck;
  walletAddress: string;
  onJwtReceived: (jwt: string) => void;
};

function Oidc({ check, walletAddress, onJwtReceived }: OwnProps) {
  const lang = useLang();
  const [userEmail, setUserEmail] = useState<string>();
  const [signedInProvider, setSignedInProvider] = useState<OidcProvider>();
  const [addressHashHead, setAddressHashHead] = useState<string>();

  useEffect(() => {
    void calcAddressSha256HeadBase64(walletAddress).then(setAddressHashHead);
  }, [walletAddress]);

  const [
    googleButtonRef, handleAppleSignIn, handleMicrosoftSignIn, handleFacebookSignIn,
  ] = useOidcProviders(addressHashHead, async (jwt: string, provider: OidcProvider) => {
    if (DEBUG) {
      // eslint-disable-next-line no-console
      console.log('Source JWT', jwt);
    }

    const parsedJwt = parseJwt(jwt);

    if (DEBUG) {
      // eslint-disable-next-line no-console
      console.log('Parsed JWT', parsedJwt);
    }

    const email = parsedJwt.payload.email;
    const { calcTargetHash2 } = await import('../util/jwt/poseidon');
    const targetHash2 = bufferFromBigInt(calcTargetHash2(email, check.salt));
    const targetHash3 = hexFromArrayBuffer(await window.crypto.subtle.digest('SHA-256', targetHash2));
    if (targetHash3 !== check.targetHash3) {
      alert(lang(`Access denied.\n\nEmail ${email} does not match the expected recipient: ${check.targetHint}`));

      return;
    }

    setSignedInProvider(provider);
    setUserEmail(email);

    onJwtReceived(jwt);
  });

  return (
    <div className={styles.container}>
      {userEmail ? (
        <>
          <div className={styles.title}>
            {lang('Authorized as %target%', { target: userEmail })}
          </div>
          <div className={styles.providerInfo}>
            <span
              className={buildClassName(styles.providerIcon, styles[`providerIcon_${signedInProvider!}`])}
              aria-hidden
            />
            {PROVIDERS[signedInProvider!].name}
          </div>
        </>
      ) : (
        <>
          <div className={styles.title}>
            {lang('Authorize as %targetHint%', { targetHint: check.targetHint })}
          </div>
          <div className={styles.description}>
            {lang('Select your provider:')}
          </div>

          <div className={styles.buttonsContainer}>
            {PUSH_GOOGLE_OAUTH_CLIENT_ID && (
              <button
                ref={googleButtonRef}
                className={styles.iconButton}
                aria-label="Sign in with Google"
                title="Sign in with Google"
              >
                <span className={buildClassName(styles.iconButtonIcon, styles.iconButtonIcon_google)} aria-hidden />
              </button>
            )}

            {PUSH_APPLE_OAUTH_CLIENT_ID && (
              <button
                className={styles.iconButton}
                onClick={handleAppleSignIn}
                aria-label="Sign in with Apple"
                title="Sign in with Apple"
              >
                <span className={buildClassName(styles.iconButtonIcon, styles.iconButtonIcon_apple)} aria-hidden />
              </button>
            )}

            {PUSH_MICROSOFT_OAUTH_CLIENT_ID && (
              <button
                className={styles.iconButton}
                onClick={handleMicrosoftSignIn}
                aria-label="Sign in with Microsoft"
                title="Sign in with Microsoft"
              >
                <span className={buildClassName(styles.iconButtonIcon, styles.iconButtonIcon_microsoft)} aria-hidden />
              </button>
            )}

            {PUSH_FACEBOOK_OAUTH_CLIENT_ID && (
              <button
                className={styles.iconButton}
                onClick={handleFacebookSignIn}
                aria-label="Sign in with Facebook"
                title="Sign in with Facebook"
              >
                <span className={buildClassName(styles.iconButtonIcon, styles.iconButtonIcon_facebook)} aria-hidden />
              </button>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default memo(Oidc);
