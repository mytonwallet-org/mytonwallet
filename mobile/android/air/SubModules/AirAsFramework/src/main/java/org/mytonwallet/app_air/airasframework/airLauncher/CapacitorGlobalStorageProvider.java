package org.mytonwallet.app_air.airasframework.airLauncher;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.webkit.WebView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.mytonwallet.app_air.walletbasecontext.logger.Logger;
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
    private static final long INITIAL_LOAD_RETRY_DELAY_MS = 500;
    private final Context context;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService persistQueue = Executors.newSingleThreadExecutor();
    private final AtomicInteger doNotSynchronize = new AtomicInteger(0);
    @Nullable
    private OnReadyCallback onReady;
    private WebView webView;
    private boolean isWebViewReady = false;
    private boolean isInitialLoadComplete = false;
    private boolean isDestroyed = false;
    private long initialLoadAttempt = 0;
    private volatile boolean isPersisting = false;
    private volatile boolean pendingPersist = false;
    private volatile long lastPersist = 0;
    private volatile JSONObject globalStorageJsonDict = new JSONObject();

    public CapacitorGlobalStorageProvider(Context context, final OnReadyCallback onReady) {
        this.context = context;
        this.onReady = onReady;
        createWebView();
    }

    private void createWebView() {
        if (isDestroyed)
            return;

        if (!isInitialLoadComplete)
            initialLoadAttempt++;

        WebView newWebView;
        try {
            newWebView = new WebView(context);
        } catch (RuntimeException error) {
            if (isInitialLoadComplete)
                throw error;
            handleInitialLoadFailure("createWebView:" + error.getClass().getSimpleName());
            return;
        }
        Logger.INSTANCE.d(
            Logger.LogTag.AIR_APPLICATION,
            "Storage createWebView: webViewId=" + System.identityHashCode(newWebView) +
                " isRecovery=" + isInitialLoadComplete +
                " initialLoadAttempt=" + initialLoadAttempt
        );
        webView = newWebView;
        isWebViewReady = false;

        WebSettings settings = newWebView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        newWebView.setWebViewClient(new CapacitorGlobalStorageWebViewClient(this));
        newWebView.loadUrl("https://mytonwallet.local/");
    }

    void onPageFinished(WebView view) {
        if (view != webView || isWebViewReady)
            return;

        isWebViewReady = true;
        Logger.INSTANCE.d(
            Logger.LogTag.AIR_APPLICATION,
            "Storage onPageFinished: webViewId=" + System.identityHashCode(view) +
                " isRecovery=" + isInitialLoadComplete
        );
        if (isInitialLoadComplete) {
            pendingPersist = false;
            persistChanges(PERSIST_INSTANT);
            return;
        }

        String script = "(function() { " +
            "var globalState = localStorage.getItem('" + GLOBAL_STATE_KEY + "'); " +
            "if (globalState) { return JSON.parse(globalState) || {}; } " +
            "return {}; })();";

        boolean didExecute = executeJS(script, result -> {
            if (isInitialLoadComplete)
                return;
            if (result != null) {
                try {
                    JSONObject loadedStorage = new JSONObject(result);
                    globalStorageJsonDict = loadedStorage;
                    isInitialLoadComplete = true;
                    notifyReady(true);
                } catch (Exception e) {
                    handleInitialLoadFailure(
                        "parseResult:" + e.getClass().getSimpleName() +
                            " resultType=" + ("null".equals(result) ? "javascript-null" : "invalid-json")
                    );
                }
            } else {
                handleInitialLoadFailure("evaluateJavascript:null-result");
            }
        });
        if (!didExecute)
            handleInitialLoadFailure("evaluateJavascript:not-executed");
    }

    private void handleInitialLoadFailure(String reason) {
        if (isDestroyed || isInitialLoadComplete)
            return;

        Logger.INSTANCE.e(
            Logger.LogTag.AIR_APPLICATION,
            "Storage initial load failed: attempt=" + initialLoadAttempt +
                " reason=" + reason +
                " retryInMs=" + INITIAL_LOAD_RETRY_DELAY_MS
        );

        WebView failedWebView = webView;
        webView = null;
        isWebViewReady = false;
        isPersisting = false;
        pendingPersist = false;
        if (failedWebView != null)
            destroyWebView(failedWebView);

        mainHandler.postDelayed(() -> {
            if (!isDestroyed && !isInitialLoadComplete && webView == null)
                createWebView();
        }, INITIAL_LOAD_RETRY_DELAY_MS);
    }

    private void notifyReady(boolean success) {
        OnReadyCallback callback = onReady;
        onReady = null;
        if (callback != null)
            callback.onReady(success);
    }

    boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
        String didCrash = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? Boolean.toString(detail.didCrash()) : "";
        String rendererPriorityAtExit = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ? Integer.toString(detail.rendererPriorityAtExit())
            : "";
        boolean isCurrentWebView = view == webView;
        Logger.INSTANCE.e(
            Logger.LogTag.AIR_APPLICATION,
            "Storage onRenderProcessGone: webViewId=" + System.identityHashCode(view) +
                " didCrash=" + didCrash +
                " rendererPriorityAtExit=" + rendererPriorityAtExit +
                " isCurrent=" + isCurrentWebView +
                " isReady=" + isWebViewReady +
                " initialLoadComplete=" + isInitialLoadComplete +
                " isPersisting=" + isPersisting +
                " pendingPersist=" + pendingPersist
        );
        if (isCurrentWebView) {
            webView = null;
            isWebViewReady = false;
            isPersisting = false;
            pendingPersist = isInitialLoadComplete;
        }
        destroyWebView(view);
        if (isCurrentWebView) {
            if (isInitialLoadComplete) {
                mainHandler.post(() -> {
                    if (webView == null)
                        createWebView();
                });
            } else {
                handleInitialLoadFailure("renderProcessGone");
            }
        }
        return true;
    }

    private boolean executeJS(String script, ValueCallback<String> callback) {
        WebView executingWebView = webView;
        if (executingWebView == null || !isWebViewReady)
            return false;

        executingWebView.evaluateJavascript(script, result -> {
            if (executingWebView == webView && isWebViewReady)
                callback.onReceiveValue(result);
        });
        return true;
    }

    private void destroyWebView(WebView view) {
        if (view.getParent() instanceof ViewGroup)
            ((ViewGroup) view.getParent()).removeView(view);
        view.destroy();
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

            String snapshot;
            synchronized (this) {
                snapshot = globalStorageJsonDict.toString();
            }
            String jsonString = JSONObject.quote(snapshot);
            String script = "(function() { " +
                "try {" +
                "localStorage.setItem('" + GLOBAL_STATE_KEY + "', " + jsonString + ");" +
                "return true;" +
                "} catch (e) {" +
                "console.log('ERROR SAVING', e);" +
                "return false;" +
                "}})();";

            mainHandler.post(() -> {
                if (!executeJS(script, result -> {
                    //Log.d("CapacitorGlobalStorageProvider", "PERSISTING");
                    try {
                        if ("true".equals(result)) {
                            Log.d("CapacitorGlobalStorageProvider", "PERSISTED");
                            isPersisting = false;
                            lastPersist = System.currentTimeMillis();
                            mainHandler.postDelayed(() -> {
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
                })) {
                    isPersisting = false;
                    pendingPersist = true;
                }
            });
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
    public void incrementDoNotSynchronize() {
        doNotSynchronize.incrementAndGet();
    }

    @Override
    public void decrementDoNotSynchronize() {
        int previousValue = doNotSynchronize.getAndUpdate(value -> value > 0 ? value - 1 : 0);
        if (previousValue == 1)
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
        isDestroyed = true;
        mainHandler.removeCallbacksAndMessages(null);
        onReady = null;
        WebView destroyedWebView = webView;
        webView = null;
        isWebViewReady = false;
        if (destroyedWebView != null)
            destroyWebView(destroyedWebView);
    }
}
