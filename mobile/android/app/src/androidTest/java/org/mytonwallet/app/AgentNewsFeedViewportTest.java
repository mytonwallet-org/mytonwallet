package org.mytonwallet.app;

import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Bundle;
import android.view.ContextThemeWrapper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Callable;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentCachedHistories;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsChatRequest;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostArrival;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVM;
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsMenuKt;
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup;
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController;
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder;
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink;
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser;
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem;
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp;
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary;
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import kotlin.Unit;
import kotlin.jvm.functions.Function1;
import kotlinx.coroutines.CoroutineScope;
import kotlinx.coroutines.CoroutineScopeKt;

@RunWith(AndroidJUnit4.class)
public class AgentNewsFeedViewportTest {
  private Context context;
  private Field globalStorageProviderField;
  private Object originalGlobalStorageProvider;

  @Before
  public void prepareNativeViews() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      context = new ContextThemeWrapper(
        InstrumentationRegistry.getInstrumentation().getTargetContext(),
        androidx.appcompat.R.style.Theme_AppCompat
      );
      ApplicationContextHolder.INSTANCE.update(context);
      LocaleController.INSTANCE.init(context, "en");
      reflect(() -> {
        Class<?> storage = Class.forName("org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage");
        globalStorageProviderField = storage.getDeclaredField("globalStorageProvider");
        globalStorageProviderField.setAccessible(true);
        originalGlobalStorageProvider = globalStorageProviderField.get(null);
        Class<?> provider = Class.forName("org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider");
        globalStorageProviderField.set(null, Proxy.newProxyInstance(
          provider.getClassLoader(), new Class<?>[]{provider}, (proxy, method, arguments) -> {
            if (method.getName().equals("contains")) return false;
            if (method.getName().equals("keysIn")) return new String[0];
            if (method.getName().startsWith("get")) return null;
            throw new AssertionError("A view test must not mutate wallet storage: " + method.getName());
          }
        ));
        Class<?> fonts = Class.forName("org.mytonwallet.app_air.uicomponents.helpers.FontManager");
        Object fontManager = fonts.getField("INSTANCE").get(null);
        fonts.getMethod("setRegular", Typeface.class).invoke(fontManager, Typeface.DEFAULT);
        fonts.getMethod("setMedium", Typeface.class).invoke(fontManager, Typeface.DEFAULT);
        fonts.getMethod("setBold", Typeface.class).invoke(fontManager, Typeface.DEFAULT_BOLD);
        Class.forName("com.facebook.drawee.backends.pipeline.Fresco")
          .getMethod("initialize", Context.class).invoke(null, context);
        return null;
      });
    });
  }

  @After
  public void restoreStorageProvider() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> reflect(() -> {
      if (globalStorageProviderField != null) globalStorageProviderField.set(null, originalGlobalStorageProvider);
      return null;
    }));
  }

  @Test
  public void paginationKeepsNewsCardVisibleBelowSameDayHeader() {
    checkPrepend(0);
  }

  @Test
  public void paginationKeepsNewsCardVisibleWhenUnreadDividerMoves() {
    checkPrepend(1);
  }

  @Test
  public void discussionPreviewBindsLoadingFollowupsBeforeThreadExists() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      AgentNewsChatRequest request = new AgentNewsChatRequest(
        42, "en", "News awaiting discussion", null, null, "Feed excerpt", null,
        "2026-10-20T12:00:00Z", "News body", Collections.emptyList(), null, false
      );
      Object controller = reflect(() -> Class.forName(
        "org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC"
      ).getConstructor(
        Context.class,
        Class.forName("org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary"),
        Class.forName("org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentPromptChatRequest"),
        AgentNewsChatRequest.class, boolean.class, Function1.class, Function1.class, String.class
      ).newInstance(context, null, null, request, false, null, null, null));
      try {
        assertNull(field(controller, "preparedVM"));
        invoke(controller, "rebuildTimeline");
        List<?> initialItems = (List<?>) field(controller, "timelineItems");
        assertEquals("Message", initialItems.get(initialItems.size() - 1).getClass().getSimpleName());
        List<?> timers = (List<?>) field(invoke(controller, "getNewsFollowupWait"), "timers");
        ((Runnable) timers.get(0)).run();
        ViewGroup recycler = (ViewGroup) field(controller, "chatRecyclerView");
        layoutViewport(recycler);

        List<?> items = (List<?>) field(controller, "timelineItems");
        Object hints = items.get(items.size() - 1);
        assertEquals("Hints", hints.getClass().getSimpleName());
        assertEquals(true, invoke(hints, "isLoading"));
        assertNotNull(invoke(hints, "getFollowupMessageId"));
        assertNull("The preview must render before the create-thread response", field(controller, "preparedVM"));

        View boundHints = null;
        View boundPost = null;
        for (int index = 0; index < recycler.getChildCount(); index++) {
          View child = recycler.getChildAt(index);
          if (child.getClass().getSimpleName().equals("AgentHintsCell")) {
            boundHints = child;
            assertEquals(true, field(child, "isLoadingRendered"));
          } else if (child.getClass().getSimpleName().equals("AgentNewsPostCell")) {
            boundPost = child;
          }
        }
        assertNotNull("The real RecyclerView must bind the loading followups", boundHints);
        assertNotNull(boundPost);
        checkFlightCancellationRestoresPreview(recycler, boundPost, boundHints);

        Object hydratedPost = invoke(items.get(1), "getMessage");
        setField(hydratedPost, "followups", Collections.singletonList(
          new AgentV2FollowUp("followup", "question", "Why does this matter?")
        ));
        List<?> hydratedItems = reflect(() -> {
          Method build = controller.getClass().getDeclaredMethod("buildTimelineItems", List.class);
          build.setAccessible(true);
          return (List<?>) build.invoke(controller, Collections.singletonList(hydratedPost));
        });
        Object hydratedHints = hydratedItems.get(hydratedItems.size() - 1);
        assertEquals("Hints must reserve their row while hydrated news is still LOADING",
          "Hints", hydratedHints.getClass().getSimpleName());
        assertEquals(true, invoke(hydratedHints, "isLoading"));

        List<Object> loadedItems = new ArrayList<>(items);
        Object loadedHints = reflect(() -> hints.getClass()
          .getConstructor(List.class, String.class, boolean.class)
          .newInstance(Collections.emptyList(), invoke(hints, "getFollowupMessageId"), false));
        loadedItems.set(loadedItems.size() - 1, loadedHints);
        boolean updatedInPlace = reflect(() -> {
          Method update = controller.getClass().getDeclaredMethod("updateOpeningTimelineInPlace", List.class);
          update.setAccessible(true);
          return (boolean) update.invoke(controller, loadedItems);
        });
        assertTrue("Replacing loading suggestions must not reset the news viewport", updatedInPlace);
        checkReadFailureKeepsNewsPreviewVisible(controller, (AgentMessage) hydratedPost);
      } finally {
        invoke(invoke(controller, "getNewsFollowupWait"), "cancel");
      }
    });
  }

  private void checkReadFailureKeepsNewsPreviewVisible(Object controller, AgentMessage failure) {
    setField(failure, "id", "read-failure");
    setField(failure, "isFailure", true);
    setField(failure, "newsPost", false);
    setField(failure, "role", AgentMessageRole.SYSTEM);
    setField(failure, "text", "Failed to load chat");
    setField(failure, "followups", Collections.emptyList());
    CoroutineScope scope = CoroutineScopeKt.MainScope();
    CoroutineScopeKt.cancel(scope, null);
    AgentVM model = new AgentVM(null, new LiveAgentV2Client(), new AgentV2ThreadSummary(
      "preview-thread", 1, null, null, null, null, 0, null, null, null, null, null, null, null
    ), Collections.singletonList(failure), null, false,
      new AgentCachedHistories(scope, () -> null, (threadId, continuation) -> null),
      scope, null, () -> 0L, () -> 0L, continuation -> Unit.INSTANCE, null, null);
    try {
      setField(model, "state", AgentVM.State.ERROR);
      setField(controller, "preparedVM", model);
      setField(controller, "agentState", AgentVM.State.ERROR);
      invoke(controller, "rebuildTimeline");
      invoke(controller, "updateLoadError");
      ViewGroup recycler = (ViewGroup) field(controller, "chatRecyclerView");
      layoutViewport(recycler);
      assertEquals("A failed history request must not cover the news preview", View.VISIBLE, recycler.getVisibility());
      assertEquals(View.GONE, ((View) field(controller, "loadErrorView")).getVisibility());
      boolean hasNews = false;
      for (int index = 0; index < recycler.getChildCount(); index++) {
        hasNews |= recycler.getChildAt(index).getClass().getSimpleName().equals("AgentNewsPostCell");
      }
      assertTrue("The real RecyclerView still displays the news card", hasNews);
      assertNotNull(reflect(() -> {
        Method retry = controller.getClass().getDeclaredMethod("buildFailureRetry", AgentMessage.class);
        retry.setAccessible(true);
        return retry.invoke(controller, failure);
      }));

      setField(controller, "news", null);
      invoke(controller, "updateLoadError");
      assertEquals("A genuinely empty failed chat still offers centered Retry", View.VISIBLE,
        ((View) field(controller, "loadErrorView")).getVisibility());
      assertEquals(View.INVISIBLE, recycler.getVisibility());
    } finally {
      setField(controller, "preparedVM", null);
      model.onDestroy();
    }
  }

  private void checkFlightCancellationRestoresPreview(View recycler, View post, View hints) {
    FrameLayout root = new FrameLayout(context);
    root.addView(recycler);
    layoutViewport(root);
    View composer = new View(context);
    composer.layout(0, 1480, 1080, 1600);
    AgentNewsPostArrival.Destination destination = reflect(() ->
      (AgentNewsPostArrival.Destination) AgentNewsPostArrival.Destination.class.getConstructors()[0]
        .newInstance(post, hints, composer)
    );
    Bitmap snapshot = Bitmap.createBitmap(240, 160, Bitmap.Config.ARGB_8888);
    AgentNewsPostArrival arrival = new AgentNewsPostArrival(
      snapshot, new Rect(24, 200, 264, 360), () -> destination, () -> 100
    );
    try {
      arrival.start(root);
      assertEquals(0f, post.getAlpha(), 0f);
      assertEquals(0f, hints.getAlpha(), 0f);
      arrival.cancel();
      assertEquals(1f, post.getAlpha(), 0f);
      assertEquals(1f, hints.getAlpha(), 0f);
      int reservedHeight = hints.getHeight();
      reflect(() -> hints.getClass().getMethod("reveal", long.class).invoke(hints, 0L));
      hints.measure(
        View.MeasureSpec.makeMeasureSpec(hints.getWidth(), View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
      );
      assertEquals("Landing must not collapse the hints and move the news post", reservedHeight, hints.getMeasuredHeight());
    } finally {
      arrival.cancel();
      snapshot.recycle();
      root.removeView(recycler);
    }
  }

  @Test
  public void newsFlightStaysVisibleBeforeComposerHasBeenLaidOut() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      FrameLayout root = new FrameLayout(context);
      layoutViewport(root);
      View composer = new View(context);
      Bitmap snapshot = Bitmap.createBitmap(240, 160, Bitmap.Config.ARGB_8888);
      snapshot.eraseColor(Color.RED);
      Bitmap rendered = Bitmap.createBitmap(1080, 1600, Bitmap.Config.ARGB_8888);
      AgentNewsPostArrival arrival = new AgentNewsPostArrival(
        snapshot, new Rect(24, 200, 264, 360),
        () -> new AgentNewsPostArrival.Destination(null, null, composer), () -> 100
      );
      try {
        arrival.start(root);
        ((Drawable) field(arrival, "flight")).draw(new Canvas(rendered));
        assertEquals("An unlaid-out input must not clip the entire card", Color.RED, rendered.getPixel(100, 250));
      } finally {
        arrival.cancel();
        snapshot.recycle();
        rendered.recycle();
      }
    });
  }

  @Test
  public void newsFlightKeepsDestinationConstraintsValidWhileScreensMove() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      FrameLayout root = new FrameLayout(context);
      ViewGroup destination = reflect(() -> (ViewGroup) Class.forName(
        "org.mytonwallet.app_air.uicomponents.widgets.WView"
      ).getConstructor(Context.class, ViewGroup.LayoutParams.class).newInstance(
        context, new ViewGroup.LayoutParams(1080, 1600)
      ));
      View composer = new View(context);
      composer.setId(View.generateViewId());
      destination.addView(composer, new ViewGroup.LayoutParams(900, 120));
      root.addView(destination);
      layoutViewport(root);
      destination.setTranslationX(400);
      destination.setClipChildren(true);
      Bitmap snapshot = Bitmap.createBitmap(240, 160, Bitmap.Config.ARGB_8888);
      int childCount = destination.getChildCount();
      int[] completions = {0};
      AgentNewsPostArrival arrival = new AgentNewsPostArrival(
        snapshot, new Rect(24, 200, 264, 360),
        () -> new AgentNewsPostArrival.Destination(null, null, composer), () -> 100
      );
      arrival.setOnFinish(() -> { completions[0]++; return Unit.INSTANCE; });
      try {
        arrival.start(root);
        // Insets and keyboard updates clone the destination constraints during the flight.
        assertNotNull(invoke(destination, "constraintSet"));
        assertEquals(childCount, destination.getChildCount());
        assertSame("The flight must remain outside the moving/clipping destination", root, field(arrival, "root"));
      } finally {
        arrival.cancel();
        arrival.cancel();
        snapshot.recycle();
      }
      assertEquals(1, completions[0]);
      assertNull(field(arrival, "root"));
      assertNull(field(arrival, "preDrawBinding"));
      assertEquals(childCount, destination.getChildCount());
      assertEquals(1f, composer.getAlpha(), 0f);
    });
  }

  private void checkPrepend(int separatorPosition) {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      Object controller = controller(context);
      Object model = field(controller, "model");
      View recycler = (View) field(controller, "recyclerView");
      Object layout = invoke(recycler, "getLayoutManager");
      recycler.setPadding(0, 40, 0, 0);
      setField(model, "items", news(31, 60));
      setField(model, "unreadEventId", 31);
      invoke(controller, "updateFeed");
      reflect(() -> layout.getClass().getMethod("scrollToPositionWithOffset", int.class, int.class)
        .invoke(layout, separatorPosition, 0));
      layoutViewport(recycler);
      assertEquals(separatorPosition, invoke(layout, "findFirstVisibleItemPosition"));
      int firstNewsPosition = 2; // Day header, unread divider, then event 31.
      View firstNews = findView(layout, firstNewsPosition);
      assertNotNull(firstNews);
      int before = firstNews.getTop();
      assertTrue(before < recycler.getHeight());

      // The delayed older page shares the day and moves the unread boundary to event 1.
      setField(model, "items", news(1, 60));
      setField(model, "unreadEventId", 1);
      setField(controller, "wasLoadingMore", true);
      invoke(controller, "updateFeed");
      layoutViewport(recycler);

      View oldNews = findView(layout, firstNewsPosition + 30);
      assertNotNull("Event 31 must remain visible after older news arrives", oldNews);
      assertEquals("Event 31 must retain its screen offset", before, oldNews.getTop());
    });
  }

  @Test
  public void shareNewsHeadlineAndLinkFromMenu() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      Intent[] launched = {null};
      Context capturingContext = new ContextWrapper(context) {
        @Override
        public void startActivity(Intent intent) {
          launched[0] = intent;
        }
      };
      for (String locale : new String[]{"ru", "en"}) {
        launched[0] = null;
        AgentNewsPostContent post = new AgentNewsPostContent(new AgentV2ThreadNewsCard(
          307, "News headline", null, null, "2026-10-20T12:00:00Z", null,
          "Full **news** body", Collections.singletonList(
            new AgentV2NewsFeedItem.Source("Source", "https://example.com/story")
          )
        ), locale);
        List<WMenuPopup.Item> items = AgentNewsMenuKt.buildAgentNewsMenuItems(
          new View(capturingContext), post, null, null
        );

        WMenuPopup.Item shareItem = items.get(items.size() - 1);
        assertEquals("Share", ((WMenuPopup.Item.Config.Item) shareItem.getConfig()).getTitle().toString());
        shareItem.getOnTap().invoke();
        assertNotNull(launched[0]);
        assertEquals(Intent.ACTION_CHOOSER, launched[0].getAction());
        assertEquals("News headline", launched[0].getCharSequenceExtra(Intent.EXTRA_TITLE));
        Intent shared = launched[0].getParcelableExtra(Intent.EXTRA_INTENT);
        assertNotNull(shared);
        assertEquals(Intent.ACTION_SEND, shared.getAction());
        assertEquals("text/plain", shared.getType());
        String sharedText = shared.getStringExtra(Intent.EXTRA_TEXT);
        assertEquals("News headline\nhttps://my.tt/agent?news=307&lang=" + locale + "&utm_source=pulse_share", sharedText);
        assertEquals(new Deeplink.Agent(null, 307, null),
          DeeplinkParser.Companion.parse(Uri.parse(sharedText.substring(sharedText.indexOf('\n') + 1))));
      }
    });
  }

  @Test
  public void httpSourceLaunchesCustomTabWithOriginalUrl() {
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      Intent[] launched = {null};
      Context capturingContext = new ContextWrapper(context) {
        @Override
        public void startActivity(Intent intent) {
          launched[0] = intent;
        }

        @Override
        public void startActivity(Intent intent, Bundle options) {
          launched[0] = intent;
        }
      };
      Object controller = controller(capturingContext);
      String url = "http://neverssl.com/";
      setField(field(controller, "model"), "items", news(1, 1));
      invoke(controller, "updateFeed");
      ViewGroup recycler = (ViewGroup) field(controller, "recyclerView");
      layoutViewport(recycler);
      View card = findView(invoke(recycler, "getLayoutManager"), 1);
      assertNotNull(card);
      @SuppressWarnings("unchecked")
      Function1<String, Unit> openSource = (Function1<String, Unit>) invoke(card, "getOnOpenSource");
      assertNotNull(openSource);
      openSource.invoke(url);

      assertNotNull("HTTP sources must leave the cleartext-blocked WebView", launched[0]);
      assertEquals(Intent.ACTION_VIEW, launched[0].getAction());
      assertEquals(url, launched[0].getDataString());
      assertTrue(launched[0].hasExtra("android.support.customtabs.extra.SESSION"));
    });
  }

  private static Object controller(Context context) {
    return reflect(() -> Class.forName(
      "org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsFeedVC"
    ).getConstructor(Context.class, Integer.class, Function1.class, List.class, String.class).newInstance(
      context, null, (Function1<String, Object>) threadId -> null, Collections.emptyList(), null
    ));
  }

  private static List<AgentV2NewsFeedItem> news(int first, int last) {
    List<AgentV2NewsFeedItem> items = new ArrayList<>();
    for (int id = first; id <= last; id++) {
      items.add(new AgentV2NewsFeedItem(
        id, String.format(Locale.ROOT, "2026-10-20T12:%02d:%02dZ", id / 60, id % 60),
        "News " + id, String.join("", Collections.nCopies(8, "Market news **summary**. ")),
        null, Collections.emptyList(), null, null
      ));
    }
    return items;
  }

  private static void layoutViewport(View recycler) {
    recycler.measure(
      View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(1600, View.MeasureSpec.EXACTLY)
    );
    recycler.layout(0, 0, recycler.getMeasuredWidth(), recycler.getMeasuredHeight());
  }

  private static View findView(Object layout, int position) {
    return (View) reflect(() -> layout.getClass().getMethod("findViewByPosition", int.class)
      .invoke(layout, position));
  }

  private static Object field(Object owner, String name) {
    return reflect(() -> accessibleField(owner, name).get(owner));
  }

  private static void setField(Object owner, String name, Object value) {
    reflect(() -> { accessibleField(owner, name).set(owner, value); return null; });
  }

  private static Field accessibleField(Object owner, String name) throws Exception {
    Field field = owner.getClass().getDeclaredField(name);
    field.setAccessible(true);
    return field;
  }

  private static Object invoke(Object owner, String name) {
    return reflect(() -> {
      Method method;
      try {
        method = owner.getClass().getMethod(name);
      } catch (NoSuchMethodException ignored) {
        method = owner.getClass().getDeclaredMethod(name);
      }
      method.setAccessible(true);
      return method.invoke(owner);
    });
  }

  private static <T> T reflect(Callable<T> operation) {
    try {
      return operation.call();
    } catch (Exception error) {
      throw new AssertionError(error);
    }
  }
}
