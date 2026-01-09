package org.mytonwallet.app_air.uicomponents.extensions

import android.animation.Animator
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.view.View
import androidx.core.animation.doOnEnd
import org.mytonwallet.app_air.uicomponents.AnimationConstants

@DslMarker
private annotation class AnimatorDsl

private sealed interface Node {
    data class Single(val animator: Animator) : Node
    data class Together(val children: List<Node>) : Node
    data class Sequential(val children: List<Node>) : Node
}

@AnimatorDsl
class WAnimatorSet {
    private val nodes: MutableList<Node> = mutableListOf()
    private var endAction: (() -> Unit)? = null

    fun onEnd(action: () -> Unit) {
        endAction = action
    }

    fun viewProperty(v: View, block: ViewAnimatorDsl.() -> Unit) {
        val animator = ViewAnimatorDsl(v).apply(block).build()
        nodes += Node.Single(animator)
    }

    fun intValues(vararg values: Int, block: IntAnimatorDsl.() -> Unit) {
        val cfg = IntAnimatorDsl().apply(block)
        val animator = ValueAnimator.ofInt(*values).apply { cfg.applyTo(this) }
        nodes += Node.Single(animator)
    }

    fun together(block: WAnimatorSet.() -> Unit) {
        val child = WAnimatorSet().apply(block)
        nodes += Node.Together(child.nodes.toList())
    }

    fun sequential(block: WAnimatorSet.() -> Unit) {
        val child = WAnimatorSet().apply(block)
        nodes += Node.Sequential(child.nodes.toList())
    }

    fun build(): Animator {
        val root: Node = when (nodes.size) {
            0 -> Node.Together(emptyList())
            1 -> nodes[0]
            else -> Node.Together(nodes.toList())
        }

        val animator = buildNode(root)
        endAction?.let { action -> animator.doOnEnd { action() } }
        return animator
    }

    private fun buildNode(node: Node): Animator = when (node) {
        is Node.Single -> node.animator
        is Node.Together -> AnimatorSet().apply {
            val kids = node.children.map { buildNode(it) }
            if (kids.isNotEmpty()) playTogether(kids)
        }

        is Node.Sequential -> AnimatorSet().apply {
            val kids = node.children.map { buildNode(it) }
            if (kids.isNotEmpty()) playSequentially(kids)
        }
    }
}

@AnimatorDsl
class ViewAnimatorDsl(private val view: View) {
    private val holders = mutableListOf<PropertyValuesHolder>()
    private var duration: Long = AnimationConstants.QUICK_ANIMATION
    private var startDelay: Long = 0L
    private var interpolator: TimeInterpolator? = null

    fun duration(duration: Long) {
        this.duration = duration
    }

    fun startDelay(startDelay: Long) {
        this.startDelay = startDelay
    }

    fun interpolator(interpolator: TimeInterpolator) {
        this.interpolator = interpolator
    }

    fun alpha(vararg values: Float) {
        holders.add(PropertyValuesHolder.ofFloat(View.ALPHA, *values))
    }

    fun translationX(vararg values: Float) {
        holders.add(PropertyValuesHolder.ofFloat(View.TRANSLATION_X, *values))
    }

    fun translationY(vararg values: Float) {
        holders.add(PropertyValuesHolder.ofFloat(View.TRANSLATION_Y, *values))
    }

    fun scaleX(vararg values: Float) {
        holders.add(PropertyValuesHolder.ofFloat(View.SCALE_X, *values))
    }

    fun scaleY(vararg values: Float) {
        holders.add(PropertyValuesHolder.ofFloat(View.SCALE_Y, *values))
    }

    fun rotation(vararg values: Float) {
        holders.add(PropertyValuesHolder.ofFloat(View.ROTATION, *values))
    }

    fun build(): ObjectAnimator {
        val dsl = this
        return ObjectAnimator.ofPropertyValuesHolder(view, *holders.toTypedArray()).apply {
            duration = dsl.duration
            startDelay = dsl.startDelay
            dsl.interpolator?.let { interpolator = it }
        }
    }
}

@AnimatorDsl
class IntAnimatorDsl {
    var duration: Long = AnimationConstants.QUICK_ANIMATION
    var startDelay: Long = 0L
    var interpolator: TimeInterpolator? = null
    private var updateAction: ((Int) -> Unit)? = null

    fun duration(duration: Long) {
        this.duration = duration
    }

    fun startDelay(startDelay: Long) {
        this.startDelay = startDelay
    }

    fun interpolator(interpolator: TimeInterpolator) {
        this.interpolator = interpolator
    }

    fun onUpdate(action: (Int) -> Unit) {
        updateAction = action
    }

    fun applyTo(animator: ValueAnimator) {
        val dsl = this
        with(animator) {
            duration = dsl.duration
            startDelay = dsl.startDelay
            dsl.interpolator?.let { interpolator = it }
            dsl.updateAction?.let { updateAction ->
                addUpdateListener { updateAction(it.animatedValue as Int) }
            }
        }
    }
}

inline fun animatorSet(block: WAnimatorSet.() -> Unit): Animator {
    return WAnimatorSet().apply(block).build()
}
