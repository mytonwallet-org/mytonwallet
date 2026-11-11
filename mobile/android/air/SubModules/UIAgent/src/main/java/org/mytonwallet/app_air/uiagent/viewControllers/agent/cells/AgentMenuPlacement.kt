package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentReactionCloudPlacement
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentReactionGeometry
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.placeAgentReactionCloud

// Telegram's chat menu: it ends this far before the finger and keeps its own height plus 56 dp over the screen's
// bottom; one taller than 240 dp rises by the excess
private const val MENU_TOUCH_GAP = 28f
private const val MENU_BOTTOM_RESERVE = 48f
private const val MENU_BOTTOM_INSET = 8f
private const val MENU_RISE_LIMIT = 240f

// Under its reactions, Telegram's menu ends this much farther before the finger
private const val MENU_CLOUD_SHIFT = 36f

/** Where a message's menu opens, its top left in the window, and its reaction cloud over it, in px */
internal data class AgentMenuPlacement(
    val left: Int,
    val top: Int,
    val cloud: AgentReactionCloudPlacement?
)

/**
 * Places a message's menu of [width] by [height] as Telegram's chat does, in window px; [density] is px per dp. The
 * menu hangs from the finger at [touchX], [touchY] and ends [MENU_TOUCH_GAP] dp before it toward the line's start;
 * one taller than [MENU_RISE_LIMIT] dp rises by the excess. It keeps between [areaLeft] and [areaRight], under
 * [minTop] and clear of [areaBottom], and one taller than the area starts at [areaTop].
 *
 * With [hasCloud], the answer's reaction cloud rides over the menu as Telegram's reactions ride over its message menu,
 * and the two move as one: the menu ends [MENU_CLOUD_SHIFT] dp farther before the finger, and the cloud's capsule
 * keeps [AgentReactionGeometry.CLOUD_AREA_INSET] inside the area and under [cloudMinTop].
 */
internal fun placeAgentMenu(
    touchX: Int,
    touchY: Int,
    width: Int,
    height: Int,
    areaLeft: Int,
    areaTop: Int,
    areaRight: Int,
    areaBottom: Int,
    minTop: Int,
    cloudMinTop: Int,
    hasCloud: Boolean,
    isRtl: Boolean,
    density: Float
): AgentMenuPlacement {
    fun px(dp: Float) = (dp * density).roundToInt()
    val touchGap = px(MENU_TOUCH_GAP + if (hasCloud) MENU_CLOUD_SHIFT else 0f)
    val cloudReach = if (hasCloud) {
        px(AgentReactionGeometry.CLOUD_MENU_OVERHANG + AgentReactionGeometry.CLOUD_AREA_INSET)
    } else {
        0
    }
    val left = if (isRtl) {
        (touchX + touchGap)
            .coerceAtMost(areaRight - width)
            .coerceAtLeast(areaLeft + cloudReach)
    } else {
        (touchX - touchGap - width)
            .coerceAtMost(areaRight - cloudReach - width)
            .coerceAtLeast(areaLeft)
    }
    val above = if (hasCloud) {
        px(AgentReactionGeometry.CLOUD_BODY_HEIGHT) + px(AgentReactionGeometry.CLOUD_MENU_GAP)
    } else {
        0
    }
    val reserved = above + height + px(MENU_BOTTOM_RESERVE)
    val unitTop = if (reserved < areaBottom - areaTop) {
        val risen = if (reserved > px(MENU_RISE_LIMIT)) {
            touchY + px(MENU_RISE_LIMIT) - reserved
        } else {
            touchY
        }
        risen.coerceAtMost(areaBottom - reserved - px(MENU_BOTTOM_INSET))
            .coerceAtLeast(if (hasCloud) max(minTop, cloudMinTop) else minTop)
    } else {
        areaTop
    }
    val top = unitTop + above
    val cloud = if (hasCloud) {
        placeAgentReactionCloud(left, top, left + width, isRtl, density)
    } else {
        null
    }
    return AgentMenuPlacement(left, top, cloud)
}
