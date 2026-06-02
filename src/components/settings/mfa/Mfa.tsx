import React, { memo, useEffect } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { selectCurrentAccount } from '../../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../../util/buildClassName';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';
import InstallMfa from './InstallMfa';
import ManageMfa from './ManageMfa';

import settingsStyles from '../Settings.module.scss';

interface OwnProps {
  isActive: boolean;
  isInsideModal?: boolean;
  isSlideActive?: boolean;
  currentAccountId: string;

  onBackClick: () => void;
  openMfaPassword: () => void;
  openMfaInstalled: () => void;
}

interface StateProps {
  installMfa?: {
    requestId: string;
    user?: {
      id: string;
    };
  };
  mfa?: {
    address: string;
    user?: {
      name: string;
      avatar?: string;
    };
  };
}

function Mfa(
  {
    onBackClick,
    isInsideModal,
    isSlideActive,
    isActive,
    openMfaPassword,
    openMfaInstalled,
    mfa,
    installMfa,
  }: OwnProps & StateProps,
) {
  const [isPasswordRequested, setPasswordRequested] = useFlag(false);
  const { clearMfaRequests, submitInstallMfa } = getActions();

  const lang = useLang();

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const isInstalled = !!mfa;

  const onBack = useLastCallback(() => {
    clearMfaRequests();
    onBackClick();
  });

  // note: since the current state in security settings is not stored in the global state, we have to resort to hacks
  useEffect(() => {
    if (installMfa?.user && !isPasswordRequested) {
      if (getHasInMemoryPassword()) {
        getInMemoryPassword()
          .then((password) => {
            submitInstallMfa({ password });
            openMfaInstalled();
          })
          .catch(() => undefined);
      } else {
        openMfaPassword();
      }

      setPasswordRequested();
    }
  }, [installMfa, openMfaPassword, openMfaInstalled, onBackClick, isPasswordRequested]);

  return (
    <div className={settingsStyles.slide}>
      {isInsideModal ? (
        <ModalHeader
          onBackButtonClick={onBack}
          className={settingsStyles.modalHeader}
          withNotch={isScrolled}
        />
      ) : (
        <div className={settingsStyles.header}>
          <Button isSimple isText onClick={onBack} className={settingsStyles.headerBack}>
            <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
        </div>
      )}

      <div
        className={buildClassName(settingsStyles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {isInstalled
          ? <ManageMfa isSlideActive={isSlideActive} openMfaPassword={openMfaPassword} />
          : <InstallMfa isActive={isActive} isSlideActive={isSlideActive} />}
      </div>
    </div>

  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { installMfa } = global.settings;
  const account = selectCurrentAccount(global);

  return {
    installMfa,
    mfa: account?.byChain.ton?.mfa,
  };
})(Mfa));
