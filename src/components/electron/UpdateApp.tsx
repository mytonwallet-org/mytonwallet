import React, {
  memo, useEffect, useState,
} from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { AppReloadReason } from '../../global/types';
import { ElectronEvent } from '../../electron/types';

import { APP_NAME, PRODUCTION_URL } from '../../config';
import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Spinner from '../ui/Spinner';

import styles from './UpdateApp.module.scss';

type StateProps = {
  isAppUpdateAvailable?: boolean;
  appReloadReason?: AppReloadReason;
};

function UpdateApp({ isAppUpdateAvailable, appReloadReason }: StateProps) {
  const lang = useLang();

  const [isElectronUpdateDownloaded, setIsElectronUpdateDownloaded] = useState(false);
  const [isElectronAutoUpdateEnabled, setIsElectronAutoUpdateEnabled] = useState(false);
  const [isInstalling, markInstalling, unmarkInstalling] = useFlag(false);

  useEffect(() => {
    const removeUpdateErrorListener = window.electron?.on?.(ElectronEvent.UPDATE_ERROR, () => {
      setIsElectronUpdateDownloaded(false);
      unmarkInstalling();
    });
    const removeUpdateDownloadedListener = window.electron?.on?.(ElectronEvent.UPDATE_DOWNLOADED, () => {
      setIsElectronUpdateDownloaded(true);
    });

    void window.electron?.getIsAutoUpdateEnabled?.().then(setIsElectronAutoUpdateEnabled);

    return () => {
      removeUpdateErrorListener?.();
      removeUpdateDownloadedListener?.();
    };
  }, [unmarkInstalling]);

  const handleClick = useLastCallback(async () => {
    if (isInstalling) {
      return;
    }

    // The running bundle has lost its chunks, which a reload fixes whatever the auto-update setting is.
    // A downloaded update relaunches the app, which fixes it too.
    if (appReloadReason && !isElectronUpdateDownloaded) {
      window.location.reload();
      return;
    }

    if (!isElectronAutoUpdateEnabled) {
      window.open(`${PRODUCTION_URL}/get`, '_blank', 'noopener');
      return;
    }

    if (isElectronUpdateDownloaded) {
      // `quitAndInstall` applies the update before relaunching, which takes several seconds without any progress events
      markInstalling();
      try {
        await window.electron?.installUpdate?.();
      } catch {
        unmarkInstalling();
      }
      return;
    }

    if (isAppUpdateAvailable) {
      window.location.reload();
    }
  });

  const { ref, shouldRender } = useShowTransition({
    isOpen: Boolean(isElectronUpdateDownloaded || isAppUpdateAvailable || appReloadReason),
    withShouldRender: true,
  });

  const isReloadOnly = appReloadReason === 'chunkLoadFailed' && !isElectronUpdateDownloaded && !isAppUpdateAvailable;

  if (!shouldRender) {
    return null; // eslint-disable-line no-null/no-null
  }

  return (
    <div
      ref={ref}
      className={buildClassName(
        styles.container,
        isInstalling && styles.installing,
      )}
      aria-busy={isInstalling}
      onClick={handleClick}
    >
      {isInstalling ? (
        <Spinner className={styles.spinner} />
      ) : (
        <div className={styles.iconWrapper}>
          <i className={buildClassName('icon-update', styles.icon)} />
        </div>
      )}

      <div className={styles.text}>
        {isInstalling
          ? lang('Updating')
          : isReloadOnly ? lang('Reload App') : lang('Update %app_name%', { app_name: APP_NAME })}
      </div>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { isAppUpdateAvailable, appReloadReason } = global;

  return { isAppUpdateAvailable, appReloadReason };
})(UpdateApp));
