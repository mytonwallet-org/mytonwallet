package org.mytonwallet.app;

import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers;
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup;
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl;
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup;
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupView;
import org.mytonwallet.app_air.uicomponents.widgets.menu.WPopupHost;
import org.mytonwallet.app_air.walletbasecontext.theme.WColor;
import org.mytonwallet.app_air.walletbasecontext.theme.WColorsKt;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import kotlin.Unit;

@RunWith(AndroidJUnit4.class)
public class TabMenuGestureTest {
  private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
  private final String[] titles = {"Wallet", "Market", "Agent", "Explore"};
  private final int[] tabIds = new int[titles.length];
  private FrameLayout fixture;
  private WClearSegmentedControl tabs;
  private WPopupHost host;
  private INavigationPopup popup;
  private float progress;
  private int selectedIndex = -1;
  private int underlyingClicks;
  private int menuSelections;
  private boolean isSourceRestoredOnSelection;

  @Before
  public void attachFixtureToAppWindow() {
    Context context = instrumentation.getTargetContext();
    Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
    assertNotNull(launch);
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    context.startActivity(launch);
    await("The native app window must be ready", () -> {
      WPopupHost candidate = PopupHelpers.INSTANCE.getPopupHost();
      return candidate != null && candidate.isAttachedToWindow() && candidate.hasWindowFocus()
        && candidate.getWindowView() != null && candidate.getWidth() > 0;
    }, 30000);
    runOnMain(() -> {
      host = PopupHelpers.INSTANCE.getPopupHost();
      Context viewContext = host.getContext();
      fixture = new FrameLayout(viewContext);
      fixture.setId(View.generateViewId());
      fixture.setBackgroundColor(WColorsKt.getColor(WColor.SecondaryBackground));
      View underneath = new View(viewContext);
      underneath.setOnClickListener(view -> underlyingClicks++);
      fixture.addView(underneath, new FrameLayout.LayoutParams(-1, -1));
      tabs = new WClearSegmentedControl(viewContext, 4f, false, 36f, false, 20, 20, 6);
      tabs.setId(View.generateViewId());
      GradientDrawable background = new GradientDrawable();
      background.setColor(WColorsKt.getColor(WColor.Background));
      background.setCornerRadius(toPixels(22));
      tabs.setBackground(background);
      List<WClearSegmentedControl.Item> items = new ArrayList<>();
      for (int index = 0; index < titles.length; index++) {
        tabIds[index] = View.generateViewId();
        items.add(new WClearSegmentedControl.Item(
          titles[index], null, null, null, null, null, tabIds[index]
        ));
      }
      tabs.setItems(items, 0, new WClearSegmentedControl.Delegate() {
        public void onIndexChanged(int to, boolean animated) { selectedIndex = to; }
        public void onItemMoved(int from, int to) {}
        public void enterReorderingMode() { throw new AssertionError("Menu gesture must not reorder tabs"); }
      });
      tabs.setOnLongPress(anchor -> {
        List<WMenuPopup.Item> menuItems = new ArrayList<>();
        for (String title : titles) {
          menuItems.add(new WMenuPopup.Item(null, title, false, () -> {
            menuSelections++;
            isSourceRestoredOnSelection = popup == null && tabs.getAlpha() == 1f;
            return Unit.INSTANCE;
          }));
        }
        progress = 0f;
        popup = WMenuPopup.Companion.present(
          anchor, menuItems, toPixels(280), 0, 0, WMenuPopup.Positioning.ALIGNED,
          null, false, false,
          WMenuPopup.BackgroundStyle.Cutout.Companion.fromView(anchor, toPixels(22), 0),
          WMenuPopup.BackdropStyle.BlurDimmed.INSTANCE, false, null,
          () -> { popup = null; return Unit.INSTANCE; },
          value -> { progress = value; return Unit.INSTANCE; },
          true, null, true, null, false, null
        );
        return true;
      });
      FrameLayout.LayoutParams tabParams = new FrameLayout.LayoutParams(toPixels(220), toPixels(44));
      tabParams.leftMargin = toPixels(16);
      tabParams.topMargin = toPixels(96);
      fixture.addView(tabs, tabParams);
      ViewGroup window = host.getWindowView();
      window.addView(fixture, window.indexOfChild(host), new ViewGroup.LayoutParams(-1, -1));
      return null;
    });
    await("The tab bar must be attached and laid out", () -> tabs.isAttachedToWindow() && tabs.getWidth() > 0);
  }

  @After
  public void removeFixture() {
    runOnMain(() -> { if (popup != null) popup.dismiss(); return null; });
    if (fixture != null) {
      await("The menu must release its source", () -> popup == null);
      runOnMain(() -> {
        tabs.setOnLongPress(null);
        if (fixture.getParent() instanceof ViewGroup) ((ViewGroup) fixture.getParent()).removeView(fixture);
        return null;
      });
    }
  }

  @Test
  public void longPressMenuStaysAnchoredAndPreservesOutsideBackAndTabGestures() {
    openByHoldingTab();
    assertEquals(-1, (int) runOnMain(() -> selectedIndex));
    View surface = runOnMain(() -> {
      WMenuPopupView menu = findMenu(host);
      assertNotNull(menu);
      return (View) menu.getParent();
    });
    Rect beforeDrag = getBounds(surface);
    drag(beforeDrag.centerX(), beforeDrag.top + toPixels(24),
      beforeDrag.centerX() + toPixels(90), beforeDrag.bottom + toPixels(160));
    assertTrue(runOnMain(() -> popup != null));
    assertEquals(beforeDrag, getBounds(surface));
    assertEquals(1f, runOnMain(surface::getScaleX), 0f);
    assertEquals(1f, runOnMain(surface::getScaleY), 0f);
    assertEquals(0, (int) runOnMain(() -> menuSelections));

    Rect fixtureBounds = getBounds(fixture);
    int outsideY = fixtureBounds.bottom - toPixels(24);
    assertTrue(outsideY > beforeDrag.bottom);
    tap(fixtureBounds.centerX(), outsideY);
    await("A tap outside closes the menu", () -> popup == null && tabs.isEnabled());
    assertEquals(0, (int) runOnMain(() -> underlyingClicks));
    assertEquals(1f, runOnMain(tabs::getAlpha), 0f);

    openByHoldingTab();
    instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);
    await("Back closes the popup before leaving the screen", () -> popup == null && tabs.isEnabled());
    assertTrue(runOnMain(fixture::isAttachedToWindow));
    assertEquals(1f, runOnMain(tabs::getAlpha), 0f);

    openByHoldingTab();
    Rect menuBounds = getBounds(runOnMain(() -> findMenu(host)));
    tap(menuBounds.centerX(), menuBounds.top + toPixels(24));
    await("Selecting a menu row closes it and runs the action", () ->
      popup == null && menuSelections == 1 && tabs.isEnabled());
    instrumentation.waitForIdleSync();
    assertEquals(1, (int) runOnMain(() -> menuSelections));
    assertTrue(runOnMain(() -> isSourceRestoredOnSelection));
    assertEquals(1f, runOnMain(tabs::getAlpha), 0f);

    Rect bar = getBounds(tabs);
    drag(bar.right - toPixels(12), bar.centerY(), bar.left + toPixels(12), bar.centerY());
    SystemClock.sleep(ViewConfiguration.getLongPressTimeout() + 100L);
    assertFalse(runOnMain(() -> popup != null));
    await("A horizontal swipe reveals the trailing tab", () -> {
      View explore = tabs.findViewById(tabIds[3]);
      Rect visible = new Rect();
      return explore != null && explore.getGlobalVisibleRect(visible) && visible.width() > toPixels(30);
    });
    Rect explore = getBounds(runOnMain(() -> tabs.findViewById(tabIds[3])));
    tap(explore.centerX(), explore.centerY());
    await("A regular tap still selects its tab", () -> selectedIndex == 3);
    assertEquals(0, (int) runOnMain(() -> underlyingClicks));
  }

  private void openByHoldingTab() {
    Rect bar = getBounds(tabs);
    long downAt = SystemClock.uptimeMillis();
    sendPointer(downAt, MotionEvent.ACTION_DOWN, bar.left + toPixels(32), bar.centerY());
    await("Holding the bar opens its menu", () -> popup != null,
      ViewConfiguration.getLongPressTimeout() + 3000L);
    sendPointer(downAt, MotionEvent.ACTION_UP, bar.left + toPixels(32), bar.centerY());
    await("Releasing the initial hold leaves the menu open", () -> popup != null && progress == 1f);
  }

  private void tap(float x, float y) {
    long downAt = SystemClock.uptimeMillis();
    sendPointer(downAt, MotionEvent.ACTION_DOWN, x, y);
    sendPointer(downAt, MotionEvent.ACTION_UP, x, y);
  }

  private void drag(float fromX, float fromY, float toX, float toY) {
    long downAt = SystemClock.uptimeMillis();
    sendPointer(downAt, MotionEvent.ACTION_DOWN, fromX, fromY);
    for (int step = 1; step <= 8; step++) {
      SystemClock.sleep(20);
      sendPointer(downAt, MotionEvent.ACTION_MOVE,
        fromX + (toX - fromX) * step / 8, fromY + (toY - fromY) * step / 8);
    }
    sendPointer(downAt, MotionEvent.ACTION_UP, toX, toY);
    instrumentation.waitForIdleSync();
  }

  private void sendPointer(long downAt, int action, float x, float y) {
    MotionEvent event = MotionEvent.obtain(downAt, SystemClock.uptimeMillis(), action, x, y, 0);
    event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
    try { instrumentation.sendPointerSync(event); } finally { event.recycle(); }
  }

  private Rect getBounds(View view) {
    return runOnMain(() -> {
      Rect bounds = new Rect();
      assertTrue(view.getGlobalVisibleRect(bounds));
      return bounds;
    });
  }

  private WMenuPopupView findMenu(View view) {
    if (view instanceof WMenuPopupView) return (WMenuPopupView) view;
    if (view instanceof ViewGroup) {
      ViewGroup group = (ViewGroup) view;
      for (int index = 0; index < group.getChildCount(); index++) {
        WMenuPopupView result = findMenu(group.getChildAt(index));
        if (result != null) return result;
      }
    }
    return null;
  }

  private int toPixels(float value) {
    return Math.round(value * instrumentation.getTargetContext().getResources().getDisplayMetrics().density);
  }

  private void await(String message, Callable<Boolean> condition) {
    await(message, condition, 5000);
  }

  private void await(String message, Callable<Boolean> condition, long timeoutMs) {
    long deadline = SystemClock.uptimeMillis() + timeoutMs;
    do {
      if (runOnMain(condition)) return;
      SystemClock.sleep(20);
    } while (SystemClock.uptimeMillis() < deadline);
    assertTrue(message, runOnMain(condition));
  }

  private <T> T runOnMain(Callable<T> operation) {
    FutureTask<T> task = new FutureTask<>(operation);
    instrumentation.runOnMainSync(task);
    try { return task.get(); } catch (Exception error) { throw new AssertionError(error); }
  }
}
