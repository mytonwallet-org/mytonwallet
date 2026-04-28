import type { TeactNode } from '../../../../lib/teact/teact';
import React, { memo } from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';

import styles from './EmptyListPlaceholder.module.scss';

interface OwnProps {
  stickerTgsUrl?: string;
  stickerPreviewUrl?: string;
  stickerSize?: number;
  isStickerActive?: boolean;
  title: TeactNode;
  description?: TeactNode;
  actionText?: TeactNode;
  className?: string;
  onActionClick?: NoneToVoidFunction;
}

function EmptyListPlaceholder({
  stickerTgsUrl,
  stickerPreviewUrl,
  stickerSize,
  isStickerActive,
  title,
  description,
  actionText,
  className,
  onActionClick,
}: OwnProps) {
  const hasSticker = Boolean(stickerTgsUrl && stickerPreviewUrl);
  const hasAction = Boolean(actionText && onActionClick);
  const hasDescription = Boolean(description);

  return (
    <div className={buildClassName(styles.root, className)}>
      {hasSticker && (
        <AnimatedIconWithPreview
          play={isStickerActive}
          tgsUrl={stickerTgsUrl}
          previewUrl={stickerPreviewUrl}
          size={stickerSize}
          className={styles.sticker}
          noLoop={false}
          nonInteractive
        />
      )}
      <div className={styles.content}>
        <p className={styles.title}>{title}</p>
        {hasDescription && <p className={styles.description}>{description}</p>}
        {hasAction && (
          <Button
            isPrimary
            isSmall
            className={styles.button}
            onClick={onActionClick}
          >
            {actionText}
          </Button>
        )}
      </div>
    </div>
  );
}

export default memo(EmptyListPlaceholder);
