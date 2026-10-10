package org.mytonwallet.app;

import android.net.Uri;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import java.util.Arrays;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mytonwallet.app_air.uiagent.agentV2.AgentActionNavigationKt;
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder;
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink;
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser;
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

@RunWith(AndroidJUnit4.class)
public class AgentActionNavigationTest {
  @Before
  public void setup() {
    ApplicationContextHolder.INSTANCE.update(
      InstrumentationRegistry.getInstrumentation().getTargetContext()
    );
  }

  @Test
  public void preservesPartialSwapWithoutInventingAmount() {
    for (String source : new String[]{null, "toncoin"}) {
      AgentV2ResolvedAction.OpenSwap action = new AgentV2ResolvedAction.OpenSwap(
        source, "trx", null, null
      );
      Uri uri = Uri.parse(AgentActionNavigationKt.buildAgentActionUrl(action));
      Deeplink.Swap deeplink = (Deeplink.Swap) DeeplinkParser.Companion.parse(uri);
      assertEquals(source, deeplink.getFrom());
      assertEquals("trx", deeplink.getTo());
      assertNull(deeplink.getAmountIn());
      assertNull(deeplink.getAmountOut());
      assertNull(uri.getQueryParameter("amountIn"));
      assertNull(uri.getQueryParameter("amountOut"));
    }
  }

  @Test
  public void rejectsMalformedPartialSwapPrefills() {
    for (String[] fields : new String[][]{
      {"", "trx", null, null},
      {null, " ", null, null},
      {"toncoin", "trx", "", "source"},
      {"toncoin", "trx", "NaN", "source"},
      {"toncoin", "trx", "Infinity", "source"},
      {"toncoin", "trx", "0", "source"},
      {"toncoin", "trx", "-1", "source"},
      {"toncoin", "trx", "1", null},
      {"toncoin", "trx", null, "source"},
      {null, "trx", "1", "source"},
      {"toncoin", null, "1", "destination"}
    }) {
      assertNull(Arrays.toString(fields), AgentActionNavigationKt.buildAgentActionUrl(
        new AgentV2ResolvedAction.OpenSwap(fields[0], fields[1], fields[2], fields[3])
      ));
    }
  }

  @Test
  public void preservesSwapAmountSideThroughNativeNavigation() {
    for (String side : new String[]{"source", "destination"}) {
      AgentV2ResolvedAction.OpenSwap action = new AgentV2ResolvedAction.OpenSwap(
        "toncoin", "solana", "1.25", side
      );
      Deeplink.Swap deeplink = (Deeplink.Swap) DeeplinkParser.Companion.parse(
        Uri.parse(AgentActionNavigationKt.buildAgentActionUrl(action))
      );
      assertEquals("toncoin", deeplink.getFrom());
      assertEquals("solana", deeplink.getTo());
      if ("source".equals(side)) {
        assertEquals(1.25, deeplink.getAmountIn(), 0);
        assertNull(deeplink.getAmountOut());
      } else {
        assertNull(deeplink.getAmountIn());
        assertEquals(1.25, deeplink.getAmountOut(), 0);
      }
    }
    assertNull(AgentActionNavigationKt.buildAgentActionUrl(
      new AgentV2ResolvedAction.OpenSwap("toncoin", "solana", "1", "unknown")
    ));
  }

  @Test
  public void preservesStakeTokenAndAmountThroughNativeNavigation() {
    AgentV2ResolvedAction.OpenStaking.StakeAmount[] amounts = {
      new AgentV2ResolvedAction.OpenStaking.StakeAmount("exact", "1.123456789"),
      new AgentV2ResolvedAction.OpenStaking.StakeAmount("all", null),
      null
    };
    for (AgentV2ResolvedAction.OpenStaking.StakeAmount amount : amounts) {
      AgentV2ResolvedAction.OpenStaking action = new AgentV2ResolvedAction.OpenStaking(
        "liquid", "toncoin", amount
      );
      Uri uri = Uri.parse(AgentActionNavigationKt.buildAgentActionUrl(action));
      assertEquals("toncoin", uri.getQueryParameter("asset"));
      Deeplink.Stake deeplink = (Deeplink.Stake) DeeplinkParser.Companion.parse(uri);
      assertEquals("toncoin", deeplink.getTokenSlug());
      String expectedAmount = amount == null ? null :
        "all".equals(amount.getKind()) ? "all" : amount.getValue();
      assertEquals(expectedAmount, deeplink.getAmount());
    }
    for (String parameter : new String[]{"asset", "token"}) {
      for (String amount : new String[]{"10", "all"}) {
        Deeplink.Stake deeplink = (Deeplink.Stake) DeeplinkParser.Companion.parse(
          Uri.parse("mtw://stake?product=liquid&" + parameter + "=toncoin&amount=" + amount)
        );
        assertEquals("toncoin", deeplink.getTokenSlug());
        assertEquals(amount, deeplink.getAmount());
      }
    }
    Deeplink.Stake bareDeeplink = (Deeplink.Stake) DeeplinkParser.Companion.parse(
      Uri.parse("mtw://stake")
    );
    assertNull(bareDeeplink.getTokenSlug());
    assertNull(bareDeeplink.getAmount());
  }

  @Test
  public void asksSendForTheMaximumOnlyWhenTheAgentDoes() {
    String url = "mtw://send/ton:UQ-recipient?token=toncoin";
    Uri maxUri = Uri.parse(AgentActionNavigationKt.buildAgentActionUrl(
      new AgentV2ResolvedAction.SendForm(url, true)
    ));
    Deeplink.Send deeplink = (Deeplink.Send) DeeplinkParser.Companion.parse(maxUri);
    assertEquals("all", deeplink.getAmount());
    assertEquals("toncoin", deeplink.getTokenSlug());
    assertEquals(url, AgentActionNavigationKt.buildAgentActionUrl(new AgentV2ResolvedAction.SendForm(url, false)));
  }

  @Test
  public void rejectsStakePrefillsWithoutValidAmountOrToken() {
    char[] oversizedCharacters = new char[129];
    Arrays.fill(oversizedCharacters, '1');
    String oversizedValue = new String(oversizedCharacters);
    for (String query : new String[]{
      "amount=1",
      "token=&amount=1",
      "token=toncoin&amount=0",
      "token=toncoin&amount=1e9",
      "asset=toncoin&token=other&amount=1",
      "asset=toncoin&amount=0",
      "token=toncoin&amount=" + oversizedValue,
      "token=" + oversizedValue + "&amount=1"
    }) {
      assertNull(query, DeeplinkParser.Companion.parse(Uri.parse("mtw://stake?" + query)));
    }
  }

  @Test
  public void rejectsAmbiguousOrInvalidSwapDestinationAmounts() {
    for (String query : new String[]{
      "amountOut=NaN",
      "amountOut=Infinity",
      "amountOut=-1",
      "amountIn=1&amountOut=2"
    }) {
      assertNull(query, DeeplinkParser.Companion.parse(Uri.parse("mtw://swap?" + query)));
    }
  }
}
