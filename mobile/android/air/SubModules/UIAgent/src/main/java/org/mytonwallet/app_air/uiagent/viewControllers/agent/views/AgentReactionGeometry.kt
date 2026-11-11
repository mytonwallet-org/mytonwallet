package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import kotlin.math.ceil
import kotlin.math.roundToInt

/**
 * The reaction cloud over an answer's menu and the reaction's emoji on the answer's corner, in dp. Horizontal offsets
 * run toward the trailing side, so RTL mirrors them.
 */
internal object AgentReactionGeometry {
    const val CLOUD_WIDTH = 108f
    const val CLOUD_BODY_HEIGHT = 56f
    const val CLOUD_ICON_SIZE = 36f

    /** The icons' leading edges, from the capsule's leading edge */
    val CLOUD_ICON_STARTS = floatArrayOf(12f, 60f)

    /** The circle behind the answer's reaction in the cloud */
    const val SELECTION_SIZE = 44f

    /**
     * The capsule rides over the menu as Telegram's reactions ride over its message menu: it ends this far beyond the
     * menu's trailing edge and this far above its top
     */
    const val CLOUD_MENU_OVERHANG = 40f
    const val CLOUD_MENU_GAP = 10f

    /**
     * The tail, where Telegram draws its bubble circles: a Ø16 bump centred on the capsule's bottom edge and a Ø8 dot
     * below it, beside the menu's top trailing corner, beyond the menu's trailing edge by these
     */
    const val CLOUD_BUMP_SIZE = 16f
    const val CLOUD_BUMP_CENTER_Y = CLOUD_BODY_HEIGHT
    const val CLOUD_BUMP_MENU_OUTSET = 8f
    const val CLOUD_DOT_SIZE = 8f
    const val CLOUD_DOT_CENTER_Y = CLOUD_BODY_HEIGHT + 15f
    const val CLOUD_DOT_MENU_OUTSET = 16f

    /** From the screen's edge: the popup area keeps 8 dp from it, the capsule 4 dp more */
    const val CLOUD_AREA_INSET = 4f

    /** The answer's reaction on its bubble's bottom trailing corner: an emoji this big */
    const val BADGE_ICON_SIZE = 22f

    /**
     * Telegram's icon animations: the still and the appear animation fill their frame about as the icon of [CLOUD_ICON_SIZE]
     * did, and so does the still in a frame of [BADGE_ICON_SIZE]; the center icon, the corner emoji's drawing, fills about
     * half of its frame
     */
    const val BADGE_ANIMATION_SIZE = 40f

    /**
     * The corner emoji's centre lies this far inside the bubble's trailing edge, and this far above its bottom edge: the
     * center icon draws the emoji down to about 9 below its centre, so it hangs about 3 below the bubble
     */
    const val BADGE_CENTER_INSET = 3f
    const val BADGE_CENTER_RISE = 6f

    /** The burst as a reaction lands, in Telegram's frame: three times the corner emoji expanded to twice its size */
    const val BURST_SIZE = BADGE_ICON_SIZE * 2 * 3
}

/**
 * The corner emoji view's side in px for [density] px per dp: the center icon's frame, even, so the emoji's centre falls
 * on a whole pixel, where a flying reaction lands
 */
internal fun agentReactionBadgeSize(density: Float): Int =
    2 * ceil(AgentReactionGeometry.BADGE_ANIMATION_SIZE / 2 * density).toInt()

/** A window rect, in px */
internal data class AgentReactionFrame(val left: Int, val top: Int, val right: Int, val bottom: Int)

/** Where the cloud goes: its frame in the window and its tail's bump's centre from the frame's left, in px */
internal data class AgentReactionCloudPlacement(val frame: AgentReactionFrame, val bumpCenterX: Int)

/**
 * Places the reaction cloud over a menu whose card spans [menuLeft] to [menuRight] from [menuTop], in window px;
 * [density] is px per dp. The capsule ends [AgentReactionGeometry.CLOUD_MENU_OVERHANG] beyond the menu's trailing edge
 * and [AgentReactionGeometry.CLOUD_MENU_GAP] above its top, and the tail hangs beside the menu's top trailing corner.
 */
internal fun placeAgentReactionCloud(
    menuLeft: Int,
    menuTop: Int,
    menuRight: Int,
    isRtl: Boolean,
    density: Float
): AgentReactionCloudPlacement {
    fun px(dp: Float) = (dp * density).roundToInt()
    val width = px(AgentReactionGeometry.CLOUD_WIDTH)
    val overhang = px(AgentReactionGeometry.CLOUD_MENU_OVERHANG)
    val left = if (isRtl) menuLeft - overhang else menuRight + overhang - width
    val top = menuTop - px(AgentReactionGeometry.CLOUD_MENU_GAP) -
        px(AgentReactionGeometry.CLOUD_BODY_HEIGHT)
    val bumpFromTrailingEdge = overhang - px(AgentReactionGeometry.CLOUD_BUMP_MENU_OUTSET)
    val bottom = top + px(
        AgentReactionGeometry.CLOUD_DOT_CENTER_Y + AgentReactionGeometry.CLOUD_DOT_SIZE / 2
    )
    val frame = AgentReactionFrame(left, top, left + width, bottom)
    return AgentReactionCloudPlacement(
        frame,
        bumpCenterX = if (isRtl) bumpFromTrailingEdge else width - bumpFromTrailingEdge
    )
}

/** The left of the cloud's icon for the reaction at [index], from the capsule's left, in px */
internal fun agentReactionCloudIconLeft(index: Int, isRtl: Boolean, density: Float): Float {
    val start = AgentReactionGeometry.CLOUD_ICON_STARTS[index] * density
    val size = AgentReactionGeometry.CLOUD_ICON_SIZE * density
    return if (isRtl) AgentReactionGeometry.CLOUD_WIDTH * density - start - size else start
}

/**
 * The centre of the corner emoji for a bubble spanning [bubbleLeft] to [bubbleRight] down to [bubbleBottom], in px, in
 * the bubble's coordinate space; [density] is px per dp
 */
internal fun agentReactionBadgeCenter(
    bubbleLeft: Int,
    bubbleRight: Int,
    bubbleBottom: Int,
    isRtl: Boolean,
    density: Float
): Pair<Int, Int> {
    val inset = (AgentReactionGeometry.BADGE_CENTER_INSET * density).roundToInt()
    val x = if (isRtl) bubbleLeft + inset else bubbleRight - inset
    return x to bubbleBottom - (AgentReactionGeometry.BADGE_CENTER_RISE * density).roundToInt()
}

/** A square of [size] dp centred on [centerX], [centerY], in window px; [density] is px per dp */
internal fun agentReactionSquare(
    centerX: Float,
    centerY: Float,
    size: Float,
    density: Float
): AgentReactionFrame {
    val half = size * density / 2
    return AgentReactionFrame(
        (centerX - half).roundToInt(),
        (centerY - half).roundToInt(),
        (centerX + half).roundToInt(),
        (centerY + half).roundToInt()
    )
}
