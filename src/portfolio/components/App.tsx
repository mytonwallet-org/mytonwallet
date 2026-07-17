import React, { memo, useEffect, useLayoutEffect, useState } from '../../lib/teact/teact';

import { MULTICHAIN_ENABLED, NEW_CHARTS_ENABLED } from '../config';
import buildClassName from '../../util/buildClassName';
import {
  IS_ANDROID,
  IS_IOS,
  IS_LINUX,
  IS_MAC_OS,
  IS_OPERA,
  IS_SAFARI,
  IS_WINDOWS,
} from '../../util/windowEnvironment';
import { fetchNetWorthHistory, fetchPnlCumulativeHistory, fetchPnlHistory } from '../utils/api';

import Transition from '../../components/ui/Transition';
import ChartPage from './ChartPage';
import LoadingPage from './LoadingPage';

import styles from './App.module.scss';

type OwnProps = {
  addresses?: string;
  baseCurrency?: string;
};

enum PageKey {
  Loading,
  Chart,
}

function App({ addresses, baseCurrency = 'USD' }: OwnProps) {
  const [netWorthData, setNetWorthData] = useState<any>();
  const [pnlCumulativeData, setPnlCumulativeData] = useState<any>();
  const [pnlData, setPnlData] = useState<any>();
  const [chartError, setChartError] = useState<string>();
  const [loadingSubtitle, setLoadingSubtitle] = useState<string>();
  const [renderKey, setRenderKey] = useState<PageKey>(PageKey.Loading);

  useLayoutEffect(applyDocumentClasses, []);

  if (!MULTICHAIN_ENABLED) {
    // Only request TON wallets, strip out other chains
    addresses = addresses
      ?.split(',')
      .filter((wallet) => wallet.startsWith('ton:'))
      .join(',');
  }

  useEffect(() => {
    if (!addresses) {
      setChartError('No wallet addresses provided');
      setRenderKey(PageKey.Chart);
      return;
    }

    const onProgress = (attempt: number, maxRetries: number) => {
      setLoadingSubtitle(`Still loading (${attempt}/${maxRetries})...`);
    };

    void Promise.all([
      fetchNetWorthHistory(addresses, baseCurrency, onProgress),
      NEW_CHARTS_ENABLED ? fetchPnlCumulativeHistory(addresses, baseCurrency, onProgress) : undefined,
      NEW_CHARTS_ENABLED ? fetchPnlHistory(addresses, baseCurrency, onProgress) : undefined,
    ])
      .then(([netWorth, pnlCumulative, pnl]) => {
        setNetWorthData(netWorth);
        setPnlCumulativeData(pnlCumulative);
        setPnlData(pnl);
        setRenderKey(PageKey.Chart);
      })
      .catch((err: Error) => {
        setChartError(err.message);
        setRenderKey(PageKey.Chart);
      });
  }, [addresses, baseCurrency]);

  function renderPage() {
    switch (renderKey) {
      case PageKey.Chart:
        return chartError ? (
          <div className={styles.error}>
            <div className={styles.errorTitle}>Error</div>
            <div className={styles.errorSubtitle}>{chartError}</div>
          </div>
        ) : !netWorthData || (NEW_CHARTS_ENABLED && (!pnlCumulativeData || !pnlData)) ? (
          <LoadingPage subtitle={loadingSubtitle} />
        ) : (
          <ChartPage
            netWorthData={netWorthData}
            pnlCumulativeData={pnlCumulativeData}
            pnlData={pnlData}
            baseCurrency={baseCurrency}
          />
        );

      default:
        return <LoadingPage subtitle={loadingSubtitle} />;
    }
  }

  return (
    <div className={styles.app}>
      <Transition
        name="fade"
        activeKey={renderKey}
        slideClassName={buildClassName(styles.appSlide, 'custom-scroll')}
      >
        {renderPage}
      </Transition>
    </div>
  );
}

export default memo(App);

function applyDocumentClasses() {
  const { documentElement } = document;

  documentElement.classList.add('is-rendered');

  if (IS_IOS) {
    documentElement.classList.add('is-ios', 'is-mobile');
  } else if (IS_ANDROID) {
    documentElement.classList.add('is-android', 'is-mobile');
  } else if (IS_MAC_OS) {
    documentElement.classList.add('is-macos');
  } else if (IS_WINDOWS) {
    documentElement.classList.add('is-windows');
  } else if (IS_LINUX) {
    documentElement.classList.add('is-linux');
  }
  if (IS_SAFARI) {
    documentElement.classList.add('is-safari');
  }
  if (IS_OPERA) {
    documentElement.classList.add('is-opera');
  }
}
