package org.mytonwallet.app;

import android.app.Activity;
import android.content.Intent;

/**
 * Flavor-scoped launcher for the Capacitor-backed classic UI. The mytonwallet
 * flavor opens LegacyActivity; the gram flavor has no classic UI and reports
 * isAvailable()=false so the Air-only path is always taken.
 */
public interface LegacyLauncher {
  boolean isAvailable();

  void launch(Activity from, Intent sourceIntent);
}
