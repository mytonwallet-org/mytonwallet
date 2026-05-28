import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiCardInfo, ApiCardsInfo, ApiMtwCardType, ApiTokenWithPrice } from '../../api/types';
import type { LangFn } from '../../hooks/useLang';

import { MTW_CARDS_MINT_BASE_URL } from '../../config';
import { selectCurrentAccountTokenBalance, selectCurrentToncoinBalance, selectMycoin } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../util/captureEvents';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Transition from '../ui/Transition';
import AvailabilityIndicator from './AvailabilityIndicator';
import CardPros from './CardPros';

import modalStyles from '../ui/Modal.module.scss';
import styles from './MintCardModal.module.scss';

export const MAP_CARD_TYPE_TO_NAME = {
  standard: 'Standard Card',
  silver: 'Silver Card',
  gold: 'Gold Card',
  platinum: 'Platinum Card',
  black: 'Black Card',
} as const;

interface OwnProps {
  cardsInfo: ApiCardsInfo;
}

interface StateProps {
  mycoinBalance: bigint;
  toncoinBalance: bigint;
  mycoin?: ApiTokenWithPrice;
}

enum CardSlides {
  Standard = 0,
  Silver,
  Gold,
  Platinum,
  Black,
}

const TOTAL_SLIDES = Object.values(CardSlides).length / 2;

function CardRoster({ cardsInfo, mycoin, mycoinBalance, toncoinBalance }: OwnProps & StateProps) {
  const { closeMintCardModal } = getActions();

  const lang = useLang();

  const transitionRef = useRef<HTMLDivElement>();
  const [currentSlide, setCurrentSlide] = useState<CardSlides>(CardSlides.Standard);
  const [nextKey, setNextKey] = useState<CardSlides>(CardSlides.Silver);

  const showNextSlide = useLastCallback(() => {
    setCurrentSlide((current) => (current === CardSlides.Black ? CardSlides.Standard : current + 1));
    setNextKey((current) => (current === CardSlides.Black ? CardSlides.Standard : current + 1));
  });

  const showPrevSlide = useLastCallback(() => {
    setCurrentSlide((current) => (current === CardSlides.Standard ? CardSlides.Black : current - 1));
    setNextKey((current) => (current === CardSlides.Standard ? CardSlides.Black : current - 1));
  });

  useEffect(() => {
    if (!IS_TOUCH_ENV) {
      return undefined;
    }

    return captureEvents(transitionRef.current!, {
      onSwipe: (e, direction) => {
        if (direction === SwipeDirection.Left) {
          showNextSlide();
          return true;
        } else if (direction === SwipeDirection.Right) {
          showPrevSlide();
          return true;
        }

        return false;
      },
      selectorToPreventScroll: '.custom-scroll',
    });
  }, []);

  function renderControls() {
    return (
      <>
        <Button
          isRound
          className={buildClassName(styles.close, modalStyles.closeButton)}
          ariaLabel={lang('Close')}
          onClick={closeMintCardModal}
        >
          <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
        </Button>
        <button
          className={buildClassName(styles.navigation, styles.navigationLeft)}
          type="button"
          aria-label={lang('Prev')}
          onClick={() => showPrevSlide()}
        >
          <i className={buildClassName(styles.navigationIcon, 'icon-chevron-left')} aria-hidden />
        </button>
        <button
          className={buildClassName(styles.navigation, styles.navigationRight)}
          type="button"
          onClick={() => showNextSlide()}
          aria-label={lang('Next')}
        >
          <i className={buildClassName(styles.navigationIcon, 'icon-chevron-right')} aria-hidden />
        </button>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: CardSlides) {
    const defaultProps = {
      lang,
      mycoin,
      mycoinBalance,
      toncoinBalance,
      currentKey,
    };

    switch (currentKey) {
      case CardSlides.Standard:
        return renderMediaCard({
          ...defaultProps,
          title: MAP_CARD_TYPE_TO_NAME.standard,
          type: 'standard',
          cardInfo: cardsInfo?.standard,
        });

      case CardSlides.Silver:
        return renderMediaCard({
          ...defaultProps,
          title: MAP_CARD_TYPE_TO_NAME.silver,
          type: 'silver',
          cardInfo: cardsInfo?.silver,
        });

      case CardSlides.Gold:
        return renderMediaCard({
          ...defaultProps,
          title: MAP_CARD_TYPE_TO_NAME.gold,
          type: 'gold',
          cardInfo: cardsInfo?.gold,
        });

      case CardSlides.Platinum:
        return renderMediaCard({
          ...defaultProps,
          title: MAP_CARD_TYPE_TO_NAME.platinum,
          type: 'platinum',
          cardInfo: cardsInfo?.platinum,
        });

      case CardSlides.Black:
        return renderMediaCard({
          ...defaultProps,
          title: MAP_CARD_TYPE_TO_NAME.black,
          type: 'black',
          cardInfo: cardsInfo?.black,
        });
    }
  }

  return (
    <>
      {renderControls()}
      <Transition
        ref={transitionRef}
        name="semiFade"
        className={buildClassName(styles.transition, 'custom-scroll')}
        activeKey={currentSlide}
        nextKey={nextKey}
      >
        {renderContent}
      </Transition>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const mycoin = selectMycoin(global);

  return {
    mycoinBalance: mycoin ? selectCurrentAccountTokenBalance(global, mycoin.slug) : 0n,
    toncoinBalance: selectCurrentToncoinBalance(global),
    mycoin,
  };
})(CardRoster));

function renderMediaCard({
  lang,
  title,
  type,
  mycoin,
  cardInfo,
  mycoinBalance,
  toncoinBalance,
  currentKey,
}: {
  lang: LangFn;
  title: string;
  type: ApiMtwCardType;
  cardInfo?: ApiCardInfo;
  mycoin?: ApiTokenWithPrice;
  mycoinBalance?: bigint;
  toncoinBalance?: bigint;
  currentKey: number;
}) {
  return (
    (
      <div className={styles.content}>
        <div className={buildClassName(styles.slide, styles[type])}>
          <video
            autoPlay
            muted
            loop
            playsInline
            poster={`${MTW_CARDS_MINT_BASE_URL}mtw_card_${type}.avif`}
            className={styles.video}
          >
            <source
              src={`${MTW_CARDS_MINT_BASE_URL}mtw_card_${type}.h264.mp4`}
              type="video/mp4; codecs=avc1.4D401E,mp4a.40.2"
            />
          </video>
          <div className={styles.slideInner}>
            {renderDots(currentKey)}
            <div className={styles.cardType}>{title}</div>
            <AvailabilityIndicator cardInfo={cardInfo} />
          </div>
        </div>
        <CardPros
          type={type}
          price={cardInfo?.price}
          mycoinBalance={mycoinBalance}
          toncoinBalance={toncoinBalance}
          mycoin={mycoin}
          isAvailable={Boolean(cardInfo?.notMinted)}
        />
      </div>
    )
  );
}

function renderDots(currentKey: number) {
  return (
    <div className={styles.dots}>
      {Array.from({ length: TOTAL_SLIDES }).map((_, index) => {
        return (
          <div key={index} className={buildClassName(styles.dot, index === currentKey && styles.dotActive)} />
        );
      })}
    </div>
  );
}
