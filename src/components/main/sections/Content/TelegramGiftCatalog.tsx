import React, { memo } from '../../../../lib/teact/teact';

import type { ApiUpdateNfts } from '../../../../api/types';
import type { buildTelegramGiftCatalog } from '../../../../global/helpers/telegramGiftCatalog';

import useLang from '../../../../hooks/useLang';

import styles from './TelegramGiftCatalog.module.scss';

interface OwnProps {
  catalog: ReturnType<typeof buildTelegramGiftCatalog>;
  inventoryStatus?: ApiUpdateNfts['inventoryStatus'];
  onSelectCollection: (address: string) => void;
}

function TelegramGiftCatalog({ catalog, inventoryStatus, onSelectCollection }: OwnProps) {
  const lang = useLang();
  const { hiddenCount } = catalog;
  const visibleCollections = catalog.collections.filter((row) => row.count > row.hiddenCount);
  const isComplete = inventoryStatus === 'complete';
  const statusText = inventoryStatus === 'error' ? lang('Gift inventory unavailable')
    : inventoryStatus === 'cached' ? lang('Gift inventory cached') : lang('Loading');

  return (
    <section
      className={styles.catalog}
      aria-label={lang('Telegram Gifts')}
      aria-busy={!isComplete && inventoryStatus !== 'error'}
    >
      <div className={styles.summary}>
        <strong>{lang('Total')}: {isComplete ? catalog.count.toLocaleString() : statusText}</strong>
        {isComplete && hiddenCount > 0 && <span>{lang('Hidden NFTs')}: {hiddenCount.toLocaleString()}</span>}
      </div>
      {visibleCollections.map(({ address, name, count, hiddenCount: hidden }) => (
        <button
          key={address}
          type="button"
          className={styles.collection}
          onClick={() => onSelectCollection(address)}
        >
          <span className={styles.label}>
            <span>{name || lang('Unnamed Collection')}</span>
            {isComplete && hidden > 0 && (
              <span className={styles.hidden}>{lang('Hidden NFTs')}: {hidden.toLocaleString()}</span>
            )}
          </span>
          <span className={styles.count}>{isComplete ? count.toLocaleString() : '…'}</span>
        </button>
      ))}
    </section>
  );
}

export default memo(TelegramGiftCatalog);
