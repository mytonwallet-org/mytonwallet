#!/usr/bin/env bash
set -euo pipefail

# Both the archive and the Linux distribution job must select the same app.
case "${APP_VARIANT:-mytonwallet}" in
  mytonwallet)
    if [ -z "${PUBLISH_REPO:-}" ] && [ "${IS_RELEASE_CANDIDATE:-}" != "1" ]; then
      # Temporarily keep Preview builds on internal TestFlight only.
      cat <<EOF
IOS_BUILD_CHANNEL=preview
IOS_EXTERNAL_BETA_ENABLED=false
IOS_APP_NAME=MyTonWallet_Preview
IOS_APP_IDENTIFIER=org.mytonwallet.app.preview
IOS_APP_IDENTIFIER_WIDGET=org.mytonwallet.app.preview.AirWidget
IOS_APP_IDENTIFIER_NOTIFICATION=org.mytonwallet.app.preview.notification-service
IOS_SCHEME=MyTonWallet_Preview
IOS_WIDGET_SCHEME=AirWidgetExtension_Preview
IOS_NOTIFICATION_SCHEME=MyTonWalletNotificationServiceExtension_Preview
IOS_PLIST_PATH=../../App/App/Resources/MyTonWallet/MyTonWallet_Preview-Info.plist
IOS_TESTFLIGHT_GROUP=${IOS_PREVIEW_TESTFLIGHT_GROUP:-My Wallet Beta external group}
EOF
    else
      cat <<EOF
IOS_BUILD_CHANNEL=main
IOS_APP_NAME=MyTonWallet
IOS_APP_IDENTIFIER=org.mytonwallet.app
IOS_APP_IDENTIFIER_WIDGET=org.mytonwallet.app.AirWidget
IOS_APP_IDENTIFIER_NOTIFICATION=org.mytonwallet.app.notification-service
IOS_SCHEME=MyTonWallet
IOS_WIDGET_SCHEME=AirWidgetExtension
IOS_NOTIFICATION_SCHEME=MyTonWalletNotificationServiceExtension
IOS_PLIST_PATH=../../App/App/Resources/MyTonWallet/Info.plist
IOS_TESTFLIGHT_GROUP=${IOS_TESTFLIGHT_GROUP:-MTW external group}
EOF
    fi
    ;;
  gram)
    cat <<EOF
IOS_BUILD_CHANNEL=gram
IOS_APP_NAME=Gram Wallet
IOS_APP_IDENTIFIER=io.gramwallet.app
IOS_APP_IDENTIFIER_WIDGET=io.gramwallet.app.widget
IOS_APP_IDENTIFIER_NOTIFICATION=io.gramwallet.app.notification-service
IOS_SCHEME=GramWallet
IOS_WIDGET_SCHEME=GramWalletWidgetExtension
IOS_NOTIFICATION_SCHEME=GramWalletNotificationServiceExtension
IOS_PLIST_PATH=../../App/App/Resources/GramWallet/Info.plist
IOS_TESTFLIGHT_GROUP=${IOS_GRAM_TESTFLIGHT_GROUP:-Gram Wallet external group}
EOF
    ;;
  *)
    echo "Unknown APP_VARIANT: $APP_VARIANT" >&2
    exit 1
    ;;
esac
