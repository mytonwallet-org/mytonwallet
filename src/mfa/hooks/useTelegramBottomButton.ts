import type { TeactNode } from '../../lib/teact/teact';
import { useEffect } from '../../lib/teact/teact';

import type { AppTheme } from '../../global/types';

import { IS_TELEGRAM_APP } from '../../config';
import { getTelegramApp } from '../../util/telegram';
import { IS_ANDROID } from '../../util/windowEnvironment';

type ButtonTypes = 'main' | 'secondary';

interface OwnProps {
  isActive?: boolean;
  type: ButtonTypes;
  isDisabled?: boolean;
  isLoading?: boolean;
  isPrimary?: boolean;
  isDestructive?: boolean;
  color?: string;
  textColor?: string;
  position?: 'top' | 'right' | 'bottom' | 'left';
  appTheme: AppTheme;
  accentColorIndex?: number;
  text: TeactNode;
  onClick?: NoneToVoidFunction;
}

const activeInstances: Record<ButtonTypes, number> = {
  main: 0,
  secondary: 0,
};
const BUTTON_COLORS = {
  light: {
    default: { text: '#3F4650', background: '#E2E3E5' },
    primary: { text: '#FFFFFF', background: '#0088CC' },
    destructive: { text: '#FFFFFF', background: '#F35B5B' },
  },
  dark: {
    default: { text: '#D8DADC', background: '#1E1E1F' },
    primary: { text: '#FFFFFF', background: '#469CEC' },
    destructive: { text: '#FFFFFF', background: '#D74A4A' },
  },
};

export default function useTelegramBottomButton({
  isActive,
  type,
  isLoading = false,
  isDisabled = false,
  isPrimary = false,
  isDestructive = false,
  appTheme,
  accentColorIndex,
  text,
  onClick,
}: OwnProps) {
  const webApp = IS_TELEGRAM_APP ? getTelegramApp() : undefined;

  const button = isActive && webApp
    ? (type === 'main' ? webApp.MainButton : webApp.SecondaryButton)
    : undefined;

  useEffect(() => {
    if (!button) return undefined;

    activeInstances[type] += 1;
    if (activeInstances[type] === 1) {
      button.show();
    }

    return () => {
      activeInstances[type] -= 1;

      requestAnimationFrame(() => {
        if (activeInstances[type] === 0) {
          button.hide();
        }
      });
    };
  }, [button, type]);

  useEffect(() => {
    if (!button) return undefined;

    if (isLoading) {
      button.showProgress();
    } else {
      button.hideProgress();
    }

    if (isDisabled || isLoading) {
      button.disable();
    } else {
      button.enable();
    }

    return () => {
      button.hideProgress();
      button.enable();
    };
  }, [button, isDisabled, isLoading]);

  useEffect(() => {
    if (!button) return;

    button.setParams({
      ...getButtonColors({
        isDestructive, isPrimary, appTheme, accentColorIndex,
      }),
      ...(!isPrimary && { position: 'bottom' }),
    });
  }, [accentColorIndex, appTheme, button, isDestructive, isPrimary]);

  useEffect(() => {
    if (!button) return;

    const textValue = typeof text === 'string' ? text : (text as string[]).join(' ');
    button.setText(textValue);

    // Workaround for Telegram Android bug
    if (IS_ANDROID) {
      button.hide();
      button.show();
    }
  }, [button, text]);

  useEffect(() => {
    if (!button || !onClick) return undefined;

    button.onClick(onClick);

    return () => {
      button.offClick(onClick);
    };
  }, [button, onClick]);
}

function getButtonColors({
  appTheme,
  isDestructive,
  isPrimary,
  accentColorIndex,
}: {
  appTheme: AppTheme;
  isDestructive?: boolean;
  isPrimary?: boolean;
  accentColorIndex?: number;
}) {
  const buttonThemeKey = isDestructive
    ? 'destructive'
    : (isPrimary ? 'primary' : 'default');
  const backgroundColor = BUTTON_COLORS[appTheme][buttonThemeKey].background;
  const textColor = buttonThemeKey === 'primary' && accentColorIndex
    ? (backgroundColor === '#FFFFFF' ? '#000000' : '#FFFFFF')
    : BUTTON_COLORS[appTheme][buttonThemeKey].text;

  return {
    color: backgroundColor,
    text_color: textColor,
  };
}
