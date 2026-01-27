package org.mytonwallet.app_air.uicomponents.extensions

import android.animation.Animator
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.view.View
import android.view.animation.LinearInterpolator
import androidx.core.animation.doOnEnd
import org.mytonwallet.app_air.uicomponents.AnimationConstants

@DslMarker
private annotation class AnimatorDsl

private sealed interface Node {
    data class Single(val animator: Animator) : Node
    data class Together(val children: List<Node>) : Node
    data class Sequential(val children: List<Node>) : Node
}

private interface IConfigurable {
    fun duration(duration: Long)
    fun startDelay(startDelay: Long)
    fun interpolator(interpolator: TimeInterpolator)
}

data class Configuration(
    val duration: Long? = null,
    val startDelay: Long? = null,
    val interpolator: TimeInterpolator? = null,
) {

    fun mergeFromParent(parent: Configuration): Configuration {
        return Configuration(
            duration = duration ?: parent.duration,
            startDelay = startDelay ?: parent.startDelay,
            interpolator = interpolator ?: parent.interpolator
        )
    }

    companion object {

        const val DEFAULT_DURATION: Long = AnimationConstants.QUICK_ANIMATION
        const val DEFAULT_START_DELAY: Long = 0L
        val DEFAULT_INTERPOLATOR: TimeInterpolator = LinearInterpolator()
    }
}

@AnimatorDsl
class WAnimatorSet(
    private val inherited: Configuration = Configuration()
) : IConfigurable {

    private var configuration: Configuration = Configuration()
    private val nodes: MutableList<Node> = mutableListOf()
    private var endAction: (() -> Unit)? = null

    private fun buildConfiguration(): Configuration {
        return configuration.mergeFromParent(inherited)
    }

    override fun duration(duration: Long) {
        configuration = configuration.copy(duration = duration)
    }

    override fun startDelay(startDelay: Long) {
        configuration = configuration.copy(startDelay = startDelay)
    }

    override fun interpolator(interpolator: TimeInterpolator) {
        configuration = configuration.copy(interpolator = interpolator)
    }

    fun onEnd(action: () -> Unit) {
        endAction = action
    }

    fun viewProperty(v: View, block: ViewAnimatorDsl.() -> Unit) {
        val animator = ViewAnimatorDsl(v, buildConfiguration()).apply(block).build()
        nodes += Node.Single(animator)
    }

    fun intValues(vararg values: Int, block: IntAnimatorDsl.() -> Unit) {
        val cfg = IntAnimatorDsl(buildConfiguration()).apply(block)
        val animator = ValueAnimator.ofInt(*values).apply { cfg.applyTo(this) }
        nodes += Node.Single(animator)
    }

    fun floatValues(vararg values: Float, block: FloatAnimatorDsl.() -> Unit) {
        val cfg = FloatAnimatorDsl(buildConfiguration()).apply(block)
        val animator = ValueAnimator.ofFloat(*values).apply { cfg.applyTo(this) }
        nodes += Node.Single(animator)
    }

    fun together(block: WAnimatorSet.() -> Unit) {
        val child = WAnimatorSet(buildConfiguration()).apply(block)
        nodes += Node.Together(child.nodes.toList())
    }

    fun sequential(block: WAnimatorSet.() -> Unit) {
        val child = WAnimatorSet(buildConfiguration()).apply(block)
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
class ViewAnimatorDsl(
    private val view: View,
    private val inherited: Configuration
) : IConfigurable {

    private var configuration: Configuration = Configuration()
    private val holders = mutableListOf<PropertyValuesHolder>()

    override fun duration(duration: Long) {
        configuration = configuration.copy(duration = duration)
    }

    override fun startDelay(startDelay: Long) {
        configuration = configuration.copy(startDelay = startDelay)
    }

    override fun interpolator(interpolator: TimeInterpolator) {
        configuration = configuration.copy(interpolator = interpolator)
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
        val configuration = this.configuration.mergeFromParent(inherited)
        return ObjectAnimator.ofPropertyValuesHolder(view, *holders.toTypedArray()).apply {
            duration = configuration.duration ?: Configuration.DEFAULT_DURATION
            startDelay = configuration.startDelay ?: Configuration.DEFAULT_START_DELAY
            interpolator = configuration.interpolator ?: Configuration.DEFAULT_INTERPOLATOR
        }
    }
}

@AnimatorDsl
class IntAnimatorDsl(private val inherited: Configuration) : IConfigurable {
    private var configuration: Configuration = Configuration()
    private var updateAction: ((Int) -> Unit)? = null

    override fun duration(duration: Long) {
        configuration = configuration.copy(duration = duration)
    }

    override fun startDelay(startDelay: Long) {
        configuration = configuration.copy(startDelay = startDelay)
    }

    override fun interpolator(interpolator: TimeInterpolator) {
        configuration = configuration.copy(interpolator = interpolator)
    }

    fun onUpdate(action: (Int) -> Unit) {
        updateAction = action
    }

    fun applyTo(animator: ValueAnimator) {
        val configuration = this.configuration.mergeFromParent(inherited)
        val dsl = this
        with(animator) {
            duration = configuration.duration ?: Configuration.DEFAULT_DURATION
            startDelay = configuration.startDelay ?: Configuration.DEFAULT_START_DELAY
            interpolator = configuration.interpolator ?: Configuration.DEFAULT_INTERPOLATOR
            dsl.updateAction?.let { updateAction ->
                addUpdateListener { updateAction(it.animatedValue as Int) }
            }
        }
    }
}

@AnimatorDsl
class FloatAnimatorDsl(private val inherited: Configuration) : IConfigurable {
    private var configuration: Configuration = Configuration()
    private var updateAction: ((Float) -> Unit)? = null

    override fun duration(duration: Long) {
        configuration = configuration.copy(duration = duration)
    }

    override fun startDelay(startDelay: Long) {
        configuration = configuration.copy(startDelay = startDelay)
    }

    override fun interpolator(interpolator: TimeInterpolator) {
        configuration = configuration.copy(interpolator = interpolator)
    }

    fun onUpdate(action: (Float) -> Unit) {
        updateAction = action
    }

    fun applyTo(animator: ValueAnimator) {
        val configuration = this.configuration.mergeFromParent(inherited)
        val dsl = this
        with(animator) {
            duration = configuration.duration ?: Configuration.DEFAULT_DURATION
            startDelay = configuration.startDelay ?: Configuration.DEFAULT_START_DELAY
            interpolator = configuration.interpolator ?: Configuration.DEFAULT_INTERPOLATOR
            dsl.updateAction?.let { updateAction ->
                addUpdateListener { updateAction(it.animatedValue as Float) }
            }
        }
    }
}

inline fun animatorSet(block: WAnimatorSet.() -> Unit): Animator {
    return WAnimatorSet().apply(block).build()
}
