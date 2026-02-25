import React, { memo, useRef } from '../../lib/teact/teact';

import { type Theme } from '../../global/types';

import {
  APP_ENV_MARKER,
  APP_NAME,
  APP_REPO_URL,
  APP_VERSION,
  IS_CORE_WALLET,
  IS_EXTENSION,
} from '../../config';
import { getHelpCenterUrl } from '../../global/helpers/getHelpCenterUrl';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { handleUrlClick } from '../../util/openUrl';
import { getBlogUrl, getTelegramNewsChannelUrl, getTelegramTipsChannelUrl } from '../../util/url';

import useAppTheme from '../../hooks/useAppTheme';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useScrolledState from '../../hooks/useScrolledState';

import Header from '../auth/Header';
import Emoji from '../ui/Emoji';
import ModalHeader from '../ui/ModalHeader';

import activityStyles from '../main/sections/Content/Activity.module.scss';
import styles from './Settings.module.scss';

import logoDarkPath from '../../assets/logoDark.svg';
import logoLightPath from '../../assets/logoLight.svg';
import helpcenterImg from '../../assets/settings/settings_helpcenter.svg';
import hotImg from '../../assets/settings/settings_hot.svg';
import videoImg from '../../assets/settings/settings_video.svg';

interface OwnProps {
  isActive?: boolean;
  isInsideModal?: boolean;
  slideClassName?: string;
  theme: Theme;
  handleBackClick: NoneToVoidFunction;
}

function SettingsAbout({
  isActive, isInsideModal, theme, slideClassName, handleBackClick,
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: handleBackClick,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const appTheme = useAppTheme(theme);
  const headerRef = useRef<HTMLHeadingElement>();
  const logoPath = appTheme === 'light' ? logoLightPath : logoDarkPath;
  const aboutExtensionTitle = lang('$about_extension_link_text', { app_name: APP_NAME });

  return (
    <div className={buildClassName(styles.slide, slideClassName)}>
      {isInsideModal ? (
        <ModalHeader
          title={lang('About %app_name%', { app_name: APP_NAME })}
          withNotch={isScrolled}
          onBackButtonClick={handleBackClick}
          className={styles.modalHeader}
        />
      ) : (
        <Header
          isActive={isActive}
          title={`${APP_NAME} ${APP_VERSION} ${APP_ENV_MARKER || ''}`}
          topTargetRef={headerRef}
          onBackClick={handleBackClick}
        />
      )}
      <div
        className={buildClassName(styles.content, styles.noTitle, 'custom-scroll')}
        onScroll={isInsideModal ? handleContentScroll : undefined}
      >
        <img src={logoPath} alt={lang('Logo')} className={styles.logo} />
        <h2 ref={headerRef} className={styles.title}>
          {APP_NAME} {APP_VERSION} {APP_ENV_MARKER}
          {!IS_CORE_WALLET && (
            <a href="https://mytonwallet.io/" target="_blank" className={styles.titleLink} rel="noreferrer">
              mytonwallet.io
            </a>
          )}
        </h2>
        <div className={buildClassName(styles.settingsBlock, styles.settingsBlock_text)}>
          <p className={styles.text}>
            {renderText(lang('$about_description1'))}
          </p>
          <p className={styles.text}>
            {renderText(lang('$about_description2'))}
          </p>
        </div>

        <p className={styles.blockTitle}>{lang('%app_name% Resources', { app_name: APP_NAME })}</p>
        <div className={styles.settingsBlock}>
          <a
            href={getTelegramTipsChannelUrl(lang.code!)}
            target="_blank"
            rel="noreferrer"
            className={styles.item}
            onClick={handleUrlClick}
          >
            <img className={styles.menuIcon} src={videoImg} alt={lang('Watch Video about Features')} />
            {lang('Watch Video about Features')}

            <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
          </a>
          <a
            href={getBlogUrl(lang.code!)}
            target="_blank"
            rel="noreferrer"
            className={styles.item}
            onClick={handleUrlClick}
          >
            <img className={styles.menuIcon} src={hotImg} alt={lang('Enjoy Monthly Updates in Blog')} />
            {lang('Enjoy Monthly Updates in Blog')}

            <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
          </a>
          <a
            href={getHelpCenterUrl(lang.code, 'home')}
            target="_blank"
            rel="noreferrer"
            className={styles.item}
            onClick={handleUrlClick}
          >
            <img className={styles.menuIcon} src={helpcenterImg} alt={lang('Learn New Things in Help Center')} />
            {lang('Learn New Things in Help Center')}

            <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
          </a>
        </div>

        <p className={styles.blockTitle}>{lang('Frequent Questions & Answers')}</p>
        <div className={buildClassName(styles.settingsBlock, styles.settingsBlock_text)}>
          {IS_EXTENSION ? (
            <>
              <h3 className={buildClassName(activityStyles.comment, styles.heading)}>
                <Emoji from="🥷" /> {lang('What is TON Proxy?')}
              </h3>
              <p className={buildClassName(styles.text, styles.textInChat)}>
                {renderText(lang('$about_extension_description1'))}{' '}
                <a
                  href="https://telegra.ph/TON-Sites-TON-WWW-and-TON-Proxy-09-29-2"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {lang('More info and demo.')}
                </a>
              </p>
            </>
          ) : (
            <>
              <h3 className={buildClassName(activityStyles.comment, activityStyles.colorIn, styles.heading)}>
                <Emoji from="🥷" /> {lang('What is TON Proxy?')}
              </h3>
              <p className={buildClassName(styles.text, styles.textInChat)}>
                {lang('$about_proxy_magic_description', {
                  extension_link: (
                    <a href="https://mytonwallet.io/" target="_blank" rel="noreferrer">
                      {renderText(aboutExtensionTitle)}
                    </a>
                  ),
                })}
              </p>
            </>
          )}
          <hr className={styles.separator} />
          <h3 className={buildClassName(activityStyles.comment, activityStyles.colorIn, styles.heading)}>
            <i className={buildClassName(styles.github, 'icon-github')} aria-hidden /> {lang('Is it open source?')}
          </h3>
          <p className={buildClassName(styles.text, styles.textInChat)}>
            {lang('$about_wallet_github', {
              github_link: (
                <a href={APP_REPO_URL} target="_blank" rel="noreferrer">
                  {renderText(lang('$about_github_link_text'))}
                </a>
              ),
            })}
          </p>
          <hr className={styles.separator} />
          <h3 className={buildClassName(activityStyles.comment, activityStyles.colorIn, styles.heading)}>
            <i
              className={buildClassName(styles.telegram, 'icon-telegram')}
              aria-hidden
            /> {lang('Is there a community?')}
          </h3>
          <p className={buildClassName(styles.text, styles.textInChat)}>
            {lang('$about_wallet_community', {
              community_link: (
                <a
                  href={getTelegramNewsChannelUrl(lang.code!)}
                  target="_blank"
                  rel="noreferrer"
                >
                  {renderText(lang('$about_community_link_text'))}
                </a>
              ),
            })}
          </p>
        </div>
      </div>
    </div>
  );
}

export default memo(SettingsAbout);
