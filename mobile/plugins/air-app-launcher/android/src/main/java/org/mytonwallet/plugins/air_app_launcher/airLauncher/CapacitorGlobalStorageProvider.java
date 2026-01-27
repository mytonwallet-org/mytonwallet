package org.mytonwallet.plugins.air_app_launcher.airLauncher;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.ViewGroup;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.webkit.WebView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider;
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

public class CapacitorGlobalStorageProvider implements IGlobalStorageProvider {
  private static final String GLOBAL_STATE_KEY = "mytonwallet-global-state";
  private final ExecutorService persistQueue = Executors.newSingleThreadExecutor();
  private final AtomicInteger doNotSynchronize = new AtomicInteger(0);
  private WebView webView;
  private volatile boolean isPersisting = false;
  private volatile boolean pendingPersist = false;
  private long lastPersist = 0;
  private volatile JSONObject globalStorageJsonDict = new JSONObject();

  public CapacitorGlobalStorageProvider(Context context, final OnReadyCallback onReady) {
    webView = new WebView(context);
    WebSettings settings = webView.getSettings();
    settings.setJavaScriptEnabled(true);
    settings.setDomStorageEnabled(true);
    webView.setWebViewClient(new CapacitorGlobalStorageWebViewClient(() -> {
      String script = "(function() { " +
        "var globalState = localStorage.getItem('" + GLOBAL_STATE_KEY + "'); " +
        "if (globalState) { return JSON.parse(globalState) || {}; } " +
        "return {}; })();";

      executeJS(script, result -> {
        if (result != null) {
          try {
            globalStorageJsonDict = new JSONObject(result);
            onReady.onReady(true);
          } catch (Exception e) {
            e.printStackTrace();
            onReady.onReady(false);
          }
        }
      });
    }));
    webView.loadUrl("https://mytonwallet.local/");
  }

  private void executeJS(String script, ValueCallback<String> callback) {
    if (webView != null) {
      webView.evaluateJavascript(script, callback);
    }
  }

  public synchronized void persistChanges(int mustPersist) {
    if (mustPersist == PERSIST_NO)
      return;
    persistQueue.submit(() -> {
      // Postpone if not a MUST and conditions are not met
      if (mustPersist != PERSIST_INSTANT && (isPersisting || doNotSynchronize.get() > 0 || lastPersist > System.currentTimeMillis() - 3000)) {
        pendingPersist = true;
        return;
      }

      isPersisting = true;

      String jsonString = JSONObject.quote(globalStorageJsonDict.toString());
      String script = "(function() { " +
        "try {" +
        "localStorage.setItem('" + GLOBAL_STATE_KEY + "', " + jsonString + ");" +
        "return true;" +
        "} catch (e) {" +
        "console.log('ERROR SAVING', e);" +
        "return false;" +
        "}})();";

      new Handler(Looper.getMainLooper()).post(() -> executeJS(script, result -> {
        //Log.d("CapacitorGlobalStorageProvider", "PERSISTING");
        try {
          if ("true".equals(result)) {
            Log.d("CapacitorGlobalStorageProvider", "PERSISTED");
            isPersisting = false;
            lastPersist = System.currentTimeMillis();
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
              if (pendingPersist) {
                pendingPersist = false;
                persistChanges(PERSIST_NORMAL);
              }
            }, 3000);
          } else {
            // Retry logic
            clearCache();
            isPersisting = false;
            persistChanges(PERSIST_INSTANT);
          }
        } catch (Exception e) {
          isPersisting = false;
        }
      }));
    });
  }

  private void clearCache() {
    doNotSynchronize.incrementAndGet();
    for (String accountId : Objects.requireNonNullElse(WGlobalStorage.INSTANCE.accountIds(null), new String[]{})) {
      remove("byAccountId." + accountId + ".activities.idsMain", PERSIST_NO);
      set("byAccountId." + accountId + ".activities.isMainHistoryEndReached", false, PERSIST_NO);
      setEmptyObject("byAccountId." + accountId + ".activities.idsBySlug", PERSIST_NO);
      setEmptyObject("byAccountId." + accountId + ".activities.isHistoryEndReachedBySlug", PERSIST_NO);
      setEmptyObject("byAccountId." + accountId + ".activities.byId", PERSIST_NO);
      setEmptyObject("byAccountId." + accountId + ".activities.newestActivitiesBySlug", PERSIST_NO);
      setEmptyObject("tokenPriceHistory.bySlug", PERSIST_NO);
    }
    doNotSynchronize.decrementAndGet();
  }

  private synchronized void setOnDict(String key, Object value) {
    try {
      globalStorageJsonDict = setOnDict(globalStorageJsonDict, new ArrayList<>(Arrays.asList(key.split("\\."))), value);
    } catch (Exception ignored) {
    }
  }

  private JSONObject setOnDict(JSONObject dict, List<String> keys, Object value) {
    try {
      if (keys.size() == 1) {
        if (value != null) {
          dict.put(keys.get(0), value);
        } else {
          dict.remove(keys.get(0));
        }
      } else {
        JSONObject val = dict.optJSONObject(keys.get(0));
        if (val == null)
          val = new JSONObject();
        Object res = setOnDict(val, keys.subList(1, keys.size()), value);
        dict.put(keys.get(0), res);
      }
      return dict;
    } catch (JSONException e) {
      throw new RuntimeException(e);
    }
  }

  private Object getValue(String key) {
    String[] keys = key.split("\\.");
    Object current = globalStorageJsonDict;

    for (String subKey : keys) {
      if (current instanceof JSONObject) {
        JSONObject currentJson = (JSONObject) current;
        if (currentJson.has(subKey)) {
          current = currentJson.opt(subKey);
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }

  @Override
  public int getDoNotSynchronize() {
    return doNotSynchronize.get();
  }

  @Override
  public void setDoNotSynchronize(int i) {
    doNotSynchronize.set(i);
    if (i == 0)
      persistChanges(PERSIST_NORMAL);
  }

  @Override
  public boolean contains(@NonNull String key) {
    return getValue(key) != null;
  }

  @Nullable
  @Override
  public Integer getInt(@NonNull String key) {
    try {
      return (Integer) getValue(key);
    } catch (ClassCastException e) {
      return null;
    }
  }

  @Nullable
  @Override
  public String getString(@NonNull String key) {
    try {
      return (String) getValue(key);
    } catch (ClassCastException e) {
      return null;
    }
  }

  @Nullable
  @Override
  public Boolean getBool(@NonNull String key) {
    try {
      return (Boolean) getValue(key);
    } catch (ClassCastException e) {
      return null;
    }
  }

  @Nullable
  @Override
  public JSONObject getDict(@NonNull String key) {
    try {
      return (JSONObject) getValue(key);
    } catch (ClassCastException e) {
      return null;
    }
  }

  @Nullable
  @Override
  public JSONArray getArray(@NonNull String key) {
    try {
      return (JSONArray) getValue(key);
    } catch (ClassCastException e) {
      return null;
    }
  }

  @Override
  public void set(@NonNull String key, @Nullable Object value, int persistInstantly) {
    setOnDict(key, value);
    persistChanges(persistInstantly);
  }

  @Override
  public void set(@NonNull Map<String, ?> items, int persistInstantly) {
    for (Map.Entry<String, ?> entry : items.entrySet()) {
      setOnDict(entry.getKey(), entry.getValue());
    }
    persistChanges(persistInstantly);
  }

  @Override
  public void setEmptyObject(@NonNull String key, int persistInstantly) {
    try {
      set(key, new JSONObject(), persistInstantly);
    } catch (Exception ignored) {
    }
  }

  @Override
  public void setEmptyObjects(@NonNull String[] keys, int persistInstantly) {
    for (String key : keys) {
      setOnDict(key, new JSONObject());
    }
    persistChanges(persistInstantly);
  }

  @Override
  public void remove(@NonNull String key, int persistInstantly) {
    set(key, null, persistInstantly);
  }

  @Override
  public void remove(@NonNull String[] keys, int persistInstantly) {
    for (String key : keys) {
      setOnDict(key, null);
    }
    persistChanges(persistInstantly);
  }

  @NonNull
  @Override
  public String[] keysIn(@NonNull String key) {
    try {
      JSONObject dict = (JSONObject) getValue(key);
      if (dict != null) {
        Iterator<String> keys = dict.keys();
        String[] keyArray = new String[dict.length()];
        int index = 0;
        while (keys.hasNext()) {
          keyArray[index++] = keys.next();
        }
        return keyArray;
      }
    } catch (Exception ignored) {
    }
    return new String[]{};
  }

  public interface OnReadyCallback {
    void onReady(boolean success);
  }

  void onDestroy() {
    if (webView.getParent() != null)
      ((ViewGroup) webView.getParent()).removeView(webView);
    webView = null;
  }
}
