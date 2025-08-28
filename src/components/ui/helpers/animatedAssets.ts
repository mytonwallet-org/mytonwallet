import { IS_CORE_WALLET } from '../../../config';

import iconAddDark from '../../../assets/lottie/add_dark.tgs';
import iconAddLight from '../../../assets/lottie/add_light.tgs';
import iconClockDark from '../../../assets/lottie/clock_dark.tgs';
import iconClockDarkBlue from '../../../assets/lottie/clock_dark_blue.tgs';
import iconClockDarkGray from '../../../assets/lottie/clock_dark_gray.tgs';
import iconClockDarkGreen from '../../../assets/lottie/clock_dark_green.tgs';
import iconClockDarkOrange from '../../../assets/lottie/clock_dark_orange.tgs';
import iconClockDarkPurple from '../../../assets/lottie/clock_dark_purple.tgs';
import iconClockDarkPurpleWhite from '../../../assets/lottie/clock_dark_purple_white.tgs';
import iconClockDarkRed from '../../../assets/lottie/clock_dark_red.tgs';
import iconClockLight from '../../../assets/lottie/clock_light.tgs';
import iconClockLightBlue from '../../../assets/lottie/clock_light_blue.tgs';
import iconClockLightGray from '../../../assets/lottie/clock_light_gray.tgs';
import iconClockLightGreen from '../../../assets/lottie/clock_light_green.tgs';
import iconClockLightOrange from '../../../assets/lottie/clock_light_orange.tgs';
import iconClockLightPurple from '../../../assets/lottie/clock_light_purple.tgs';
import iconClockLightPurpleWhite from '../../../assets/lottie/clock_light_purple_white.tgs';
import iconClockLightRed from '../../../assets/lottie/clock_light_red.tgs';
import coreWalletLogo from '../../../assets/lottie/core_wallet_logo.tgs';
import bill from '../../../assets/lottie/duck_bill.tgs';
import forge from '../../../assets/lottie/duck_forges.tgs';
import guard from '../../../assets/lottie/duck_guard.tgs';
import happy from '../../../assets/lottie/duck_happy.tgs';
import hello from '../../../assets/lottie/duck_hello.tgs';
import noData from '../../../assets/lottie/duck_no-data.tgs';
import run from '../../../assets/lottie/duck_run.tgs';
import snitch from '../../../assets/lottie/duck_snitch.tgs';
import thumbUp from '../../../assets/lottie/duck_thumb.tgs';
import holdTon from '../../../assets/lottie/duck_ton.tgs';
import wait from '../../../assets/lottie/duck_wait.tgs';
import yeee from '../../../assets/lottie/duck_yeee.tgs';
import iconEarnDark from '../../../assets/lottie/earn_dark.tgs';
import iconEarnDarkPurple from '../../../assets/lottie/earn_dark_purple.tgs';
import iconEarnLight from '../../../assets/lottie/earn_light.tgs';
import iconEarnLightPurple from '../../../assets/lottie/earn_light_purple.tgs';
import iconSendDark from '../../../assets/lottie/send_dark.tgs';
import iconSendLight from '../../../assets/lottie/send_light.tgs';
import iconSwapDark from '../../../assets/lottie/swap_dark.tgs';
import iconSwapLight from '../../../assets/lottie/swap_light.tgs';
import iconClockPreviewDark from '../../../assets/lottiePreview/clock_dark.svg';
import iconClockPreviewDarkBlue from '../../../assets/lottiePreview/clock_dark_blue.svg';
import iconClockPreviewDarkGray from '../../../assets/lottiePreview/clock_dark_gray.svg';
import iconClockPreviewDarkGreen from '../../../assets/lottiePreview/clock_dark_green.svg';
import iconClockPreviewDarkOrange from '../../../assets/lottiePreview/clock_dark_orange.svg';
import iconClockPreviewDarkPurple from '../../../assets/lottiePreview/clock_dark_purple.svg';
import iconClockPreviewDarkPurpleWhite from '../../../assets/lottiePreview/clock_dark_purple_white.svg';
import iconClockPreviewDarkRed from '../../../assets/lottiePreview/clock_dark_red.svg';
import iconClockPreviewLight from '../../../assets/lottiePreview/clock_light.svg';
import iconClockPreviewLightBlue from '../../../assets/lottiePreview/clock_light_blue.svg';
import iconClockPreviewLightGray from '../../../assets/lottiePreview/clock_light_gray.svg';
import iconClockPreviewLightGreen from '../../../assets/lottiePreview/clock_light_green.svg';
import iconClockPreviewLightOrange from '../../../assets/lottiePreview/clock_light_orange.svg';
import iconClockPreviewLightPurple from '../../../assets/lottiePreview/clock_light_purple.svg';
import iconClockPreviewLightPurpleWhite from '../../../assets/lottiePreview/clock_light_purple_white.svg';
import iconClockPreviewLightRed from '../../../assets/lottiePreview/clock_light_red.svg';
import coreWalletLogoPreview from '../../../assets/lottiePreview/core_wallet_logo.png';
import billPreview from '../../../assets/lottiePreview/duck_bill.png';
import forgePreview from '../../../assets/lottiePreview/duck_forges.png';
import guardPreview from '../../../assets/lottiePreview/duck_guard.png';
import happyPreview from '../../../assets/lottiePreview/duck_happy.png';
import helloPreview from '../../../assets/lottiePreview/duck_hello.png';
import noDataPreview from '../../../assets/lottiePreview/duck_no-data.png';
import runPreview from '../../../assets/lottiePreview/duck_run.png';
import snitchPreview from '../../../assets/lottiePreview/duck_snitch.png';
import thumbUpPreview from '../../../assets/lottiePreview/duck_thumb.png';
import holdTonPreview from '../../../assets/lottiePreview/duck_ton.png';
import waitPreview from '../../../assets/lottiePreview/duck_wait.png';
import yeeePreview from '../../../assets/lottiePreview/duck_yeee.png';

export const ANIMATED_STICKERS_PATHS = {
  hello,
  snitch,
  bill,
  thumbUp,
  holdTon,
  happy,
  noData,
  forge,
  wait,
  run,
  yeee,
  guard,
  helloPreview,
  snitchPreview,
  billPreview,
  thumbUpPreview,
  holdTonPreview,
  happyPreview,
  noDataPreview,
  forgePreview,
  waitPreview,
  runPreview,
  yeeePreview,
  guardPreview,
  ...(IS_CORE_WALLET && {
    coreWalletLogo,
    coreWalletLogoPreview,
  }),
  light: {
    iconAdd: iconAddLight,
    iconClock: iconClockLight,
    iconClockBlue: iconClockLightBlue,
    iconClockGray: iconClockLightGray,
    iconClockGreen: iconClockLightGreen,
    iconClockOrange: iconClockLightOrange,
    iconClockPurple: iconClockLightPurple,
    iconClockPurpleWhite: iconClockLightPurpleWhite,
    iconClockRed: iconClockLightRed,
    iconEarn: iconEarnLight,
    iconEarnPurple: iconEarnLightPurple,
    iconSend: iconSendLight,
    iconSwap: iconSwapLight,
    preview: {
      iconClock: iconClockPreviewLight,
      iconClockBlue: iconClockPreviewLightBlue,
      iconClockGray: iconClockPreviewLightGray,
      iconClockGreen: iconClockPreviewLightGreen,
      iconClockOrange: iconClockPreviewLightOrange,
      iconClockPurple: iconClockPreviewLightPurple,
      iconClockPurpleWhite: iconClockPreviewLightPurpleWhite,
      iconClockRed: iconClockPreviewLightRed,
    },
  },
  dark: {
    iconAdd: iconAddDark,
    iconClock: iconClockDark,
    iconClockBlue: iconClockDarkBlue,
    iconClockGray: iconClockDarkGray,
    iconClockGreen: iconClockDarkGreen,
    iconClockOrange: iconClockDarkOrange,
    iconClockPurple: iconClockDarkPurple,
    iconClockPurpleWhite: iconClockDarkPurpleWhite,
    iconClockRed: iconClockDarkRed,
    iconEarn: iconEarnDark,
    iconEarnPurple: iconEarnDarkPurple,
    iconSend: iconSendDark,
    iconSwap: iconSwapDark,
    preview: {
      iconClock: iconClockPreviewDark,
      iconClockBlue: iconClockPreviewDarkBlue,
      iconClockGray: iconClockPreviewDarkGray,
      iconClockGreen: iconClockPreviewDarkGreen,
      iconClockOrange: iconClockPreviewDarkOrange,
      iconClockPurple: iconClockPreviewDarkPurple,
      iconClockPurpleWhite: iconClockPreviewDarkPurpleWhite,
      iconClockRed: iconClockPreviewDarkRed,
    },
  },
};
