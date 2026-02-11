import React, { memo, useEffect } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPromotion } from '../../../api/types/backend';

import renderText from '../../../global/helpers/renderText';
import { selectCurrentAccountState } from '../../../global/selectors';
import { openUrl } from '../../../util/openUrl';
import { preloadImage } from '../../../util/preloadImage';
import { IS_ANDROID } from '../../../util/windowEnvironment';

import useLastCallback from '../../../hooks/useLastCallback';

import AvailabilityIndicator from '../../mintCard/AvailabilityIndicator';
import Button from '../../ui/Button';
import Image from '../../ui/Image';
import Modal from '../../ui/Modal';
import ModalHeader from '../../ui/ModalHeader';

import styles from './PromotionModal.module.scss';

interface StateProps {
  promotion?: ApiPromotion;
  isOpen?: boolean;
}

function PromotionModal({ promotion, isOpen }: StateProps) {
  const modal = promotion?.modal;
  const heroImageUrl = modal?.heroImageUrl;
  const { closePromotionModal } = getActions();

  const handleAction = useLastCallback(() => {
    const { actionButton } = modal || {};
    if (actionButton?.url) {
      void openUrl(actionButton.url, { isExternal: true });
    }
    closePromotionModal();
  });

  useEffect(() => {
    if (modal?.backgroundImageUrl) {
      void preloadImage(modal.backgroundImageUrl);
    }
    if (modal?.heroImageUrl) {
      void preloadImage(modal?.heroImageUrl);
    }
  }, [modal?.backgroundImageUrl, modal?.heroImageUrl]);

  if (!modal) {
    return undefined;
  }

  const injectedStyle = (
    `--promo-modal-bg: url(${modal.backgroundImageUrl}), ${modal.backgroundFallback};`
    + `--promo-title-color: ${modal.titleColor ?? '#FFFFFF'};`
    + `--promo-description-color: ${modal.descriptionColor ?? 'rgba(255, 255, 255, 0.75)'};`
  );

  return (
    <Modal
      isOpen={isOpen}
      isCompact={IS_ANDROID}
      dialogClassName={styles.modalDialog}
      contentClassName={styles.content}
      onClose={closePromotionModal}
    >
      <div className={styles.background} style={injectedStyle}>
        <ModalHeader className={styles.header} closeClassName={styles.closeButton} onClose={closePromotionModal} />

        <div className={styles.surface}>
          {heroImageUrl && (
            <div className={styles.hero}>
              <Image url={heroImageUrl} alt="" imageClassName={styles.hero_img} />
            </div>
          )}

          <div className={styles.body}>
            {modal.title && <div className={styles.title}>{modal.title}</div>}
            {modal.description && (
              <p className={styles.description}>{renderText(modal.description)}</p>
            )}
            {modal.availabilityIndicator && (
              <AvailabilityIndicator
                label={modal.availabilityIndicator}
                className={styles.availabilityIndicator}
                progress={1}
              />
            )}
            {modal.actionButton && (
              <Button
                isPrimary
                className={styles.actionButton}
                onClick={handleAction}
              >
                {modal.actionButton.title}
              </Button>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => ({
  promotion: selectCurrentAccountState(global)?.config?.activePromotion,
  isOpen: global.isPromotionModalOpen,
}))(PromotionModal));
