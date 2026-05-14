package org.mytonwallet.app;

import android.app.Activity;
import android.content.Intent;

public final class LegacyLauncherImpl implements LegacyLauncher {
  @Override
  public boolean isAvailable() {
    return true;
  }

  @Override
  public void launch(Activity from, Intent sourceIntent) {
    Intent intent = new Intent(from, LegacyActivity.class);
    intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
    intent.setAction(sourceIntent.getAction());
    intent.setData(sourceIntent.getData());
    if (sourceIntent.getExtras() != null) {
      intent.putExtras(sourceIntent.getExtras());
    }
    from.startActivity(intent);
    from.overridePendingTransition(0, 0);
    from.finish();
  }
}
