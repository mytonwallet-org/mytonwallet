package org.mytonwallet.app;

import android.content.Context;
import android.view.ContextThemeWrapper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mytonwallet.app_air.uicomponents.commonViews.InfoBannerStackView;
import org.mytonwallet.app_air.uicomponents.helpers.FontManager;
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage;
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController;
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder;
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider;
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage;
import org.mytonwallet.app_air.walletcore.moshi.ApiPromotion;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public class InfoBannerStackViewPrivacyTest {
  @Test
  public void privacyChangesMaskVisibleAndAccessibleAmountsWithoutNewBanners() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      Context context = new ContextThemeWrapper(
        InstrumentationRegistry.getInstrumentation().getTargetContext(),
        androidx.appcompat.R.style.Theme_AppCompat
      );
      ApplicationContextHolder.INSTANCE.update(context.getApplicationContext());
      WBaseStorage.INSTANCE.init(context);
      LocaleController.INSTANCE.init(context, "en");
      WGlobalStorage.INSTANCE.init(new TestStorage());
      FontManager.INSTANCE.init(context);
      Map<String, String> values = new HashMap<>();
      values.put("%amount%", "12345.67");
      values.put("%symbol%", "TON");
      values.put("%apy%", "4");
      ApiPromotion promotion = new ApiPromotion(
        "foreign-staking:ton:tonstakers", "foreignStaking", null, null,
        new ApiPromotion.InfoBanner(
          "Stake %amount% %symbol%",
          "Move %amount% %symbol% for %apy%% APY",
          new ApiPromotion.InfoBanner.ActionButton(
            "Move %amount% %symbol%", "unstakeForeign", "ton", "tonstakers"
          ),
          values
        ),
        "foreign-staking:ton"
      );
      InfoBannerStackView view = new InfoBannerStackView(context);
      view.configure(Collections.singletonList(promotion), false);
      assertTrue(textIn(view).stream().anyMatch(text -> text.contains("12345.67")));

      WGlobalStorage.INSTANCE.toggleSensitiveDataHidden();
      view.updateProtectedView();
      assertMasked(view);

      InfoBannerStackView initiallyHiddenView = new InfoBannerStackView(context);
      initiallyHiddenView.configure(Collections.singletonList(promotion), false);
      assertMasked(initiallyHiddenView);

      WGlobalStorage.INSTANCE.toggleSensitiveDataHidden();
      view.updateProtectedView();
      assertTrue(textIn(view).stream().anyMatch(text -> text.contains("12345.67")));
      assertFalse(textIn(view).stream().anyMatch(text -> text.contains("***")));
    });
  }

  private void assertMasked(InfoBannerStackView view) {
    List<String> text = textIn(view);
    assertFalse(text.stream().anyMatch(value -> value.contains("12345.67")));
    assertTrue(text.contains("Stake *** TON"));
    assertTrue(text.contains("Move *** TON for 4% APY"));
    assertTrue(text.contains("Move *** TON"));
    assertTrue(view.getChildAt(0).getContentDescription().toString().contains("*** TON"));
  }

  private List<String> textIn(View view) {
    List<String> text = new ArrayList<>();
    if (view.getContentDescription() != null) text.add(view.getContentDescription().toString());
    if (view instanceof TextView) text.add(((TextView) view).getText().toString());
    if (view instanceof ViewGroup) {
      ViewGroup group = (ViewGroup) view;
      for (int i = 0; i < group.getChildCount(); i++) text.addAll(textIn(group.getChildAt(i)));
    }
    return text;
  }

  private static class TestStorage implements IGlobalStorageProvider {
    private final Map<String, Object> values = new HashMap<>();

    TestStorage() { values.put("stateVersion", 62); }

    public void incrementDoNotSynchronize() {}
    public void decrementDoNotSynchronize() {}
    public boolean contains(String key) { return values.containsKey(key); }
    public Integer getInt(String key) { return (Integer) values.get(key); }
    public String getString(String key) { return (String) values.get(key); }
    public Boolean getBool(String key) { return (Boolean) values.get(key); }
    public JSONObject getDict(String key) { return (JSONObject) values.get(key); }
    public JSONArray getArray(String key) { return (JSONArray) values.get(key); }
    public String[] keysIn(String key) { return new String[0]; }
    public void set(String key, Object value, int persistInstantly) { values.put(key, value); }
    public void set(Map<String, ?> items, int persistInstantly) { values.putAll(items); }
    public void setEmptyObject(String key, int persistInstantly) { values.put(key, new JSONObject()); }
    public void setEmptyObjects(String[] keys, int persistInstantly) {
      for (String key : keys) setEmptyObject(key, persistInstantly);
    }
    public void remove(String key, int persistInstantly) { values.remove(key); }
    public void remove(String[] keys, int persistInstantly) {
      for (String key : keys) values.remove(key);
    }
  }
}
