import { useEffect, useRef } from '../../lib/teact/teact';

import {
  PUSH_APPLE_OAUTH_CLIENT_ID,
  PUSH_FACEBOOK_OAUTH_CLIENT_ID,
  PUSH_GOOGLE_OAUTH_CLIENT_ID,
  PUSH_MICROSOFT_OAUTH_CLIENT_ID,
} from '../config';
import { base64UrlFromBuffer, bufferFromBase64Url } from '../../util/casting';

import useLastCallback from '../../hooks/useLastCallback';

export type OidcProvider = 'google' | 'apple' | 'microsoft' | 'facebook';

export const PROVIDERS = {
  google: {
    name: 'Google',
    scriptUrl: 'https://accounts.google.com/gsi/client',
    clientId: PUSH_GOOGLE_OAUTH_CLIENT_ID,
  },
  apple: {
    name: 'Apple',
    scriptUrl: 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js',
    clientId: PUSH_APPLE_OAUTH_CLIENT_ID,
  },
  microsoft: {
    name: 'Microsoft',
    // MSAL CDN URL format: https://alcdn.msauth.net/browser/{version}/js/msal-browser.min.js
    // Find latest version at: https://github.com/AzureAD/microsoft-authentication-library-for-js/releases
    scriptUrl: 'https://alcdn.msauth.net/browser/2.38.0/js/msal-browser.min.js',
    clientId: PUSH_MICROSOFT_OAUTH_CLIENT_ID,
  },
  facebook: {
    name: 'Facebook',
    clientId: PUSH_FACEBOOK_OAUTH_CLIENT_ID,
  },
};

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (config: any) => void;
          renderButton: (element: HTMLElement, config: any) => void;
        };
      };
    };
    AppleID?: {
      auth: {
        init: (config: any) => void;
        signIn: () => Promise<any>;
      };
    };
    msal?: any;
    msalInstance?: any;
  }
}

export function useOidcProviders(
  nonce: string | undefined,
  onJwtReceived: (jwt: string, provider: OidcProvider) => void,
) {
  const handleJwtReceived = useLastCallback(onJwtReceived);
  const googleButtonRef = useRef<HTMLButtonElement>();
  const initedProvidersSetRef = useRef(new Set());

  useEffect(() => {
    if (!nonce) return;

    if (PUSH_GOOGLE_OAUTH_CLIENT_ID && !initedProvidersSetRef.current.has('google')) {
      createScript(PROVIDERS.google.scriptUrl, () => {
        window.google!.accounts.id.initialize({
          client_id: PUSH_GOOGLE_OAUTH_CLIENT_ID,
          callback: handleGoogleCredentialResponse,
          auto_select: false,
          cancel_on_tap_outside: true,
          nonce,
        });

        // Set up click handler on our custom button
        if (googleButtonRef.current) {
          googleButtonRef.current.onclick = () => {
            // Create a temporary div to render Google's button
            const tempDiv = document.createElement('div');
            tempDiv.style.position = 'fixed';
            tempDiv.style.left = '-9999px';
            document.body.appendChild(tempDiv);

            window.google!.accounts.id.renderButton(tempDiv, {
              theme: 'filled_blue',
              size: 'large',
              type: 'standard',
            });

            // Click the rendered button
            setTimeout(() => {
              const googleBtn = tempDiv.querySelector('div[role="button"]') as HTMLElement;
              if (googleBtn) {
                googleBtn.click();
              }
              // Clean up
              setTimeout(() => {
                document.body.removeChild(tempDiv);
              }, 100);
            }, 0);
          };
        }

        initedProvidersSetRef.current.add('google');
      });
    }

    if (PUSH_APPLE_OAUTH_CLIENT_ID && !initedProvidersSetRef.current.has('apple')) {
      createScript(PROVIDERS.apple.scriptUrl, () => {
        window.AppleID!.auth.init({
          clientId: PUSH_APPLE_OAUTH_CLIENT_ID,
          scope: 'email',
          redirectURI: window.location.origin,
          state: 'initial',
          nonce,
          usePopup: true,
        });

        initedProvidersSetRef.current.add('apple');
      });
    }

    if (PUSH_MICROSOFT_OAUTH_CLIENT_ID && !initedProvidersSetRef.current.has('microsoft')) {
      createScript(PROVIDERS.microsoft.scriptUrl, () => {
        window.msalInstance = new window.msal.PublicClientApplication({
          auth: {
            clientId: PUSH_MICROSOFT_OAUTH_CLIENT_ID,
            authority: 'https://login.microsoftonline.com/common',
            redirectUri: window.location.origin,
            postLogoutRedirectUri: window.location.origin,
          },
          cache: {
            cacheLocation: 'sessionStorage',
            storeAuthStateInCookie: false,
          },
        });

        initedProvidersSetRef.current.add('microsoft');
      });
    }

    if (PUSH_FACEBOOK_OAUTH_CLIENT_ID && !initedProvidersSetRef.current.has('facebook')) {
      // Facebook OIDC doesn't require initialization

      initedProvidersSetRef.current.add('facebook');
    }
  }, [googleButtonRef, nonce]);

  const handleGoogleCredentialResponse = useLastCallback((response: any) => {
    handleJwtReceived(response.credential, 'google');
  });

  const handleAppleSignIn = useLastCallback(async () => {
    const response = await window.AppleID!.auth.signIn();

    handleJwtReceived(response.authorization.id_token, 'apple');
  });

  const handleMicrosoftSignIn = useLastCallback(async () => {
    const response = await window.msalInstance.loginPopup({
      scopes: ['email'],
      nonce,
      state: nonce, // CSRF protection
      prompt: 'select_account',
    });

    handleJwtReceived(response.idToken, 'microsoft');
  });

  const handleFacebookSignIn = useLastCallback(async () => {
    if (!nonce) return;

    const { codeVerifier, codeChallenge } = await generatePkceInputs();

    // Store code verifier for later use
    sessionStorage.setItem('fb_code_verifier', codeVerifier);

    const params = new URLSearchParams({
      client_id: PUSH_FACEBOOK_OAUTH_CLIENT_ID!,
      redirect_uri: window.location.origin,
      response_type: 'code id_token',
      scope: 'openid email',
      nonce,
      state: nonce,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
    });
    const authUrl = `https://www.facebook.com/v18.0/dialog/oauth?${params.toString()}`;
    const popup = window.open(authUrl, 'facebook-login', 'width=500,height=600');

    // Listen for the response
    const checkInterval = setInterval(() => {
      try {
        if (popup?.location.href.includes(window.location.origin)) {
          clearInterval(checkInterval);

          const urlParams = new URLSearchParams(popup.location.hash.substring(1));
          const idToken = urlParams.get('id_token');

          if (idToken) {
            handleJwtReceived(idToken, 'facebook');
          }

          popup.close();
        }
      } catch (err) {
        // Cross-origin error, continue checking
      }
    }, 500);

    // Cleanup on timeout
    setTimeout(() => {
      clearInterval(checkInterval);
      if (popup && !popup.closed) popup.close();
    }, 1000 * 60 * 2); // 2-minute timeout
  });

  return [googleButtonRef, handleAppleSignIn, handleMicrosoftSignIn, handleFacebookSignIn] as const;
}

function createScript(src: string, onLoad: NoneToVoidFunction) {
  const scriptEl = document.createElement('script');

  scriptEl.src = src;
  scriptEl.async = true;
  scriptEl.defer = true;
  scriptEl.onload = onLoad;

  document.head.appendChild(scriptEl);
}

async function generatePkceInputs() {
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);

  return { codeVerifier, codeChallenge };
}

function generateCodeVerifier() {
  const array = new Uint8Array(32);

  crypto.getRandomValues(array);

  return base64UrlFromBuffer(Buffer.from(array));
}

async function generateCodeChallenge(verifierBase64: string) {
  const data = bufferFromBase64Url(verifierBase64);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const digestBuffer = Buffer.from(digest);

  return base64UrlFromBuffer(digestBuffer);
}
