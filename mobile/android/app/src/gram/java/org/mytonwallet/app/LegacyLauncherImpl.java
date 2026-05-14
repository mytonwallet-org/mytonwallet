package org.mytonwallet.app;

import android.app.Activity;
import android.content.Intent;

public final class LegacyLauncherImpl implements LegacyLauncher {
  @Override
  public boolean isAvailable() {
    return false;
  }

  @Override
  public void launch(Activity from, Intent sourceIntent) {
    // Gram has no classic UI; this is a no-op. MainActivity guards on
    // isAvailable() and never reaches here.
  }
}
