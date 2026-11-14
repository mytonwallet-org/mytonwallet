package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.InputFilter
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatEditText
import androidx.core.view.isInvisible
import androidx.core.widget.doAfterTextChanged
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationCancelDirection
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationFailure
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationState
import org.mytonwallet.app_air.uiagent.agentV2.filterDraftEdit
import org.mytonwallet.app_air.uiagent.agentV2.getAgentDictationFailureText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_COMPOSER_FIELD_TOP
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.emoji.EmojiHelper
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.ScrollLockHost
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.scaleIn
import org.mytonwallet.app_air.uicomponents.widgets.scaleOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

// Text-secondary at 8%
private const val DISABLED_SEND_FILL_ALPHA = 20

// The strip keeps this far from the field's sides
private const val STRIP_INSET = 16

// The microphone's glass circle beside the empty field, and the gap between them, as on iOS
private const val MICROPHONE_SIZE = 48
private const val MICROPHONE_GAP = 12
private const val STOP_SIZE = 14
private const val STOP_RADIUS = 3.5f
private const val STOP_START_SCALE = 0.4f
private const val STOP_MORPH_MS = 220L

// The circle shrinks this far as it merges into the field's end, where the send button comes
private const val MERGED_MICROPHONE_SCALE = 0.6f
private const val SEPARATION_MS = 400L
private const val DRAFT_FADE_MS = 400L
private const val TRANSCRIPT_FADE_MS = 200L
private val TELEGRAM_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)
private const val IDLE_SIDE_INSET = 16
private const val FIELD_TEXT_TOP_MARGIN = 2.5f
private const val KEYBOARD_SIDE_INSET = 10

// The keyboard's own pace in the chat viewport
private const val SIDE_INSET_DURATION_MS = 220L

// A mostly vertical swipe down the focused field, this far or this fast, puts the keyboard away
private const val KEYBOARD_SWIPE_DISTANCE = 24
private const val KEYBOARD_SWIPE_VELOCITY = 500
private const val MILLISECONDS_PER_SECOND = 1000

@SuppressLint("ViewConstructor")
class AgentComposerView(context: Context, private val blurRootView: ViewGroup? = null) :
    WFrameLayout(context),
    WThemedView {

    var onSend: ((String) -> Boolean)? = null

    /** Called by Stop, which the microphone turns into while the Agent answers */
    var onStop: (() -> Unit)? = null

    /** The Agent is answering, so the empty field offers to stop the answer */
    var isAnswering = false
        set(value) {
            if (field == value) return
            field = value
            applySendButtonTheme()
        }
    var onDraftCleared: (() -> Unit)? = null

    /** The field started or stopped recording, recognizing or holding a draft ([isAgentFieldInUse]) */
    var onFieldInUseChanged: ((Boolean) -> Unit)? = null
    var isFieldInUse = false
        private set

    private val inputBackground = WFrameLayout(context)
    var onHeightChanged: (() -> Unit)? = null

    /** Called as the field takes or gives up the keyboard's focus */
    var onInputFocusChanged: ((Boolean) -> Unit)? = null

    /** Called as the window gains or loses focus, as when a system dialog comes over it */
    var onWindowFocusChanged: ((Boolean) -> Unit)? = null

    /** The field's side margin as it changes, in px */
    var onSideInsetChanged: ((Int) -> Unit)? = null

    /** How far the field's bottom edge lies above the composer's */
    val inputBottomInset: Int
        get() = paddingBottom

    /** How far the field's top edge, the composer's visible top, lies below the composer's own */
    val fieldTop: Int
        get() = inputBackground.top + inputBackground.translationY.roundToInt()

    /** The opacity of the field's text and its buttons' icons over their glass, halved while a limit blocks sending */
    var contentAlpha = 1f
        set(value) {
            if (field == value) return
            field = value
            applyContentColors()
            applySendButtonTheme()
        }

    private val editText = AppCompatEditText(context).apply {
        id = UIComponentsR.id.agent_input
        isSaveEnabled = false
        setTextSize(TypedValue.COMPLEX_UNIT_SP, adaptiveFontSize())
        typeface = WFont.Regular.typeface
        hint = LocaleController.getString("Ask anything")
        maxLines = 5
        inputType = EditorInfo.TYPE_CLASS_TEXT or
            EditorInfo.TYPE_TEXT_FLAG_CAP_SENTENCES or
            EditorInfo.TYPE_TEXT_FLAG_MULTI_LINE
        imeOptions = EditorInfo.IME_ACTION_SEND
        background = null
        setPaddingRelative(16.dp, 10.dp, 16.dp, 10.dp)
    }

    /** The field's text while it is empty */
    var placeholder: CharSequence?
        get() = editText.hint
        set(value) {
            if (editText.hint?.toString() != value?.toString()) editText.hint = value
        }

    private val sendButton = ImageView(context).apply {
        id = UIComponentsR.id.agent_send
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        scaleX = 0f
        scaleY = 0f
    }

    private val microphoneButton = ImageView(context).apply {
        id = UIComponentsR.id.agent_microphone
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_dictation_start")
        setImageResource(org.mytonwallet.app_air.uiagent.R.drawable.ic_agent_microphone)
    }

    // While an answer is being written, the microphone turns into Stop wherever it would show: a filled square, as in
    // ChatGPT's and Telegram's stop states. It lets the microphone's touches through, and UI automation finds Stop by
    // its id while it shows.
    private val stopIcon = View(context).apply {
        id = UIComponentsR.id.agent_stop
        visibility = INVISIBLE
        background = GradientDrawable().apply { cornerRadius = STOP_RADIUS.dp }
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        alpha = 0f
    }
    private var isStopShown = false
    private var stopProgress = 0f
    private var stopAnimator: ValueAnimator? = null

    // The microphone's own glass circle beside the field, which it merges into while the field has text
    private val microphoneCircle = WFrameLayout(context).apply {
        addView(microphoneButton, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(stopIcon, LayoutParams(STOP_SIZE.dp, STOP_SIZE.dp, Gravity.CENTER))
    }
    private var microphoneGlass: WGlassView? = null

    // 1 while the microphone's circle stands apart from the field, 0 while merged into its end
    private var separation = 1f
    private var separationTarget = 1f
    private var separationAnimator: ValueAnimator? = null

    // A host's morph of the field and the circle out of its own pieces; see [setHostedMorph]
    private var hostedAppearance = 1f
    private var hostedSwell = 1f
    private var hostedGrowFrom = 1f
    private val recordingStrip = AgentDictationStrip(context).apply { visibility = GONE }

    // Telegram's light while a question is recognised and its transcript comes in: in the field, and round its border
    private val fieldGlow = AgentFieldGlowView(context)
    private val fieldRim = AgentFieldGlowView(context, isRim = true)

    // The rim's bloom spills well beyond the field and past the containers round it, so the rim lies over the field in
    // the window's overlay, which nothing clips, and follows it there every frame while it shows
    private var rimHost: ViewGroup? = null
    private val rimLocation = IntArray(2)
    private val rimHostLocation = IntArray(2)
    private val rimFollower = ViewTreeObserver.OnPreDrawListener {
        if (fieldRim.isLit) followField()
        true
    }

    // A transcript comes into the field character by character
    private val transcriptReveal = AgentTranscriptReveal(editText).apply {
        onFinished = { updateGlow() }
    }

    // Grows out of the microphone while recording, over everything else
    private val recordingCircle = AgentDictationCircle(microphoneButton).apply {
        onVisibilityChanged = { isShown -> onRecordingCircleVisibilityChanged?.invoke(isShown) }
        onCoverChanged = { cover ->
            recordingCover = cover
            applyMicrophoneCircle()
        }
        onPauseToggled = {
            if (dictationState.isPaused) dictation?.resume() else dictation?.pause()
        }
    }

    // How much the recording circle stands in for the microphone's own circle, which then shows only the rest
    private var recordingCover = 0f

    /** The recording circle shows over the chat, or has gone */
    var onRecordingCircleVisibilityChanged: ((Boolean) -> Unit)? = null

    /**
     * Asked as the microphone is pressed to start a recording: true holds it back and takes the press, as while the
     * Agent asks for the user's consent first
     */
    var shouldHoldDictation: (() -> Boolean)? = null
    private var dictation: AgentDictationController? = null
    private var dictationState = AgentDictationState()
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var isMicrophoneGesture = false
    private var isGestureEndClick = false
    private var microphoneVelocity: VelocityTracker? = null
    private val scrollLockReleases = ArrayList<() -> Unit>()

    private var keyboardSwipeStartX = 0f
    private var keyboardSwipeStartY = 0f
    private var keyboardSwipeVelocity: VelocityTracker? = null

    private var isSendEnabled = false

    // Unset until the first theme pass lays out the button slot
    private var isSendShown: Boolean? = null
    private var isSubmissionEnabled = true
    private var lastHeight = 0
    private var isApplyingEmoji = false
    private var inputGlass: WGlassView? = null

    private val cancelDirection: AgentDictationCancelDirection
        get() = if (LocaleController.isRTL) {
            AgentDictationCancelDirection.RIGHT
        } else {
            AgentDictationCancelDirection.LEFT
        }

    init {
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        setPaddingDp(IDLE_SIDE_INSET, AGENT_COMPOSER_FIELD_TOP, IDLE_SIDE_INSET, 8)
        clipChildren = false
        clipToPadding = false

        inputBackground.minimumHeight = 48.dp
        inputBackground.addView(fieldGlow, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        inputBackground.addView(
            editText,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.TOP
                topMargin = FIELD_TEXT_TOP_MARGIN.dp.roundToInt()
            }
        )

        sendButton.layoutParams = LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.BOTTOM
            marginEnd = 4.dp
            bottomMargin = 4.dp
        }
        inputBackground.addView(sendButton)
        // The strip spans the field, as iOS's does; the microphone's circle stands beside it
        inputBackground.addView(
            recordingStrip,
            LayoutParams(MATCH_PARENT, 48.dp).apply {
                gravity = Gravity.BOTTOM
                marginStart = STRIP_INSET.dp
                marginEnd = STRIP_INSET.dp
            }
        )

        addView(
            inputBackground,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                marginEnd = (MICROPHONE_SIZE + MICROPHONE_GAP).dp
            }
        )
        addView(
            microphoneCircle,
            LayoutParams(MICROPHONE_SIZE.dp, MICROPHONE_SIZE.dp).apply {
                gravity = Gravity.END or Gravity.BOTTOM
            }
        )
        inputGlass = WGlassView.attachTo(
            inputBackground,
            24f.dp,
            GlassProviders.composer(WColor.SearchFieldBackground),
            blurRootView
        )
        microphoneGlass = WGlassView.attachTo(
            microphoneCircle,
            (MICROPHONE_SIZE / 2f).dp,
            GlassProviders.composer(WColor.SearchFieldBackground),
            blurRootView
        )

        editText.setOnFocusChangeListener { _, hasFocus -> onInputFocusChanged?.invoke(hasFocus) }
        editText.filters = editText.filters + InputFilter { _, _, _, original, start, end ->
            if (transcriptReveal.isAppending) {
                null
            } else {
                dictationState.filterDraftEdit(original, start, end)
                    ?: transcriptReveal.filterEdit(original, start, end)
            }
        }
        editText.setOnTouchListener { _, event ->
            if (dictationState.isActive) return@setOnTouchListener true
            trackKeyboardSwipe(event)
            false
        }
        editText.doAfterTextChanged { editable ->
            if (!isApplyingEmoji && editable != null) {
                isApplyingEmoji = true
                EmojiHelper.replaceEmojiInPlace(editable, editText)
                isApplyingEmoji = false
            }
            updateSendButtonState()
            updateFieldInUse()
            if (editable.isNullOrEmpty()) onDraftCleared?.invoke()
        }

        sendButton.setOnClickListener { trySend() }
        // A locked recording finishes from the checkmark over the microphone; with TalkBack the
        // microphone starts and finishes a hands-free recording. The click that ends a hold does
        // neither, so a recording locked by that hold keeps going once the finger lifts.
        microphoneButton.setOnClickListener {
            if (isStopShown) {
                // While a draft merges the circle into the field, still showing Stop, the send
                // button grows in where the circle goes: a tap there sends, as on iOS and the web,
                // where Stop goes once the field has text
                if (editText.text.isNullOrBlank()) {
                    onStop?.invoke()
                } else if (isSendEnabled) {
                    trySend()
                }
                return@setOnClickListener
            }
            if (isGestureEndClick) return@setOnClickListener
            val state = dictationState
            if (state.phase == AgentDictationPhase.RECORDING && state.locked) {
                dictation?.finish()
            } else if (shouldHoldDictation?.invoke() != true) {
                dictation?.startHandsFree()
            }
        }
        microphoneButton.setOnTouchListener { _, event -> handleMicrophoneTouch(event) }
        recordingStrip.onCancel = { dictation?.cancel() }

        editText.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                trySend()
                true
            } else {
                false
            }
        }

        // On a physical keyboard Return sends, and with Shift, Alt, Ctrl or Meta it starts a new line. The on-screen
        // keyboard's Return always starts a new line, as on iOS.
        editText.setOnKeyListener { _, keyCode, event ->
            val isPhysicalReturn = keyCode == KeyEvent.KEYCODE_ENTER && !isSoftKeyboardKey(event)
            if (isPhysicalReturn && event.action == KeyEvent.ACTION_DOWN) {
                if (event.hasNoModifiers()) {
                    trySend()
                } else {
                    insertLineBreak()
                }
            }
            isPhysicalReturn
        }

        updateTheme()
    }

    // The swipe counts only while the field shows its first line, so it doesn't take over scrolling
    private fun trackKeyboardSwipe(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                keyboardSwipeVelocity?.recycle()
                val isFirstLineShown = !editText.canScrollVertically(-1)
                keyboardSwipeVelocity = if (editText.hasFocus() && isFirstLineShown) {
                    VelocityTracker.obtain().apply { addMovement(event) }
                } else {
                    null
                }
                keyboardSwipeStartX = event.rawX
                keyboardSwipeStartY = event.rawY
            }

            MotionEvent.ACTION_MOVE -> {
                val tracker = keyboardSwipeVelocity ?: return
                tracker.addMovement(event)
                if (isKeyboardSwipe(event, velocity = 0f)) dismissKeyboardBySwipe()
            }

            MotionEvent.ACTION_UP -> {
                val tracker = keyboardSwipeVelocity ?: return
                tracker.addMovement(event)
                tracker.computeCurrentVelocity(MILLISECONDS_PER_SECOND)
                if (isKeyboardSwipe(event, tracker.yVelocity)) dismissKeyboardBySwipe()
                endKeyboardSwipe()
            }

            MotionEvent.ACTION_CANCEL -> endKeyboardSwipe()
        }
    }

    private fun isKeyboardSwipe(event: MotionEvent, velocity: Float): Boolean {
        // A finger held for a long press, or one selecting text, is choosing text, not swiping
        if (editText.hasSelection() ||
            event.eventTime - event.downTime > ViewConfiguration.getLongPressTimeout()
        ) {
            return false
        }
        val distance = event.rawY - keyboardSwipeStartY
        val across = abs(event.rawX - keyboardSwipeStartX)
        if (distance <= 0f || distance < across * 2) return false
        return distance > KEYBOARD_SWIPE_DISTANCE.dp || velocity > KEYBOARD_SWIPE_VELOCITY.dp
    }

    private fun dismissKeyboardBySwipe() {
        endKeyboardSwipe()
        editText.hideKeyboard()
    }

    private fun endKeyboardSwipe() {
        keyboardSwipeVelocity?.recycle()
        keyboardSwipeVelocity = null
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        measureChildWithMargins(inputBackground, widthMeasureSpec, 0, heightMeasureSpec, 0)
        val inputHeight = inputBackground.measuredHeight + paddingTop + paddingBottom
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(
                resolveSize(inputHeight, heightMeasureSpec),
                MeasureSpec.EXACTLY
            )
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        followField()
        if (height != lastHeight) {
            lastHeight = height
            onHeightChanged?.invoke()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        (rootView as? ViewGroup)?.let { root ->
            rimHost = root
            root.overlay.add(fieldRim)
        }
        viewTreeObserver.addOnPreDrawListener(rimFollower)
        followField()
    }

    override fun onDetachedFromWindow() {
        transcriptReveal.finish()
        recordingCircle.detach()
        endMicrophoneGesture()
        viewTreeObserver.removeOnPreDrawListener(rimFollower)
        rimHost?.overlay?.remove(fieldRim)
        rimHost = null
        super.onDetachedFromWindow()
    }

    /**
     * Puts a transcript into the field character by character, each out of a blur, as iOS does. Without motion, and for
     * TalkBack, which reads the field as it comes, the whole text fades in.
     */
    internal fun setDictationText(text: String) {
        val canReveal = isAttachedToWindow && WGlobalStorage.getAreAnimationsActive() &&
            ValueAnimator.areAnimatorsEnabled() && !isAccessibilityEnabled()
        if (canReveal) {
            transcriptReveal.start(text)
            updateGlow()
            return
        }
        setDraftText(text, focusInput = false)
        if (!isAttachedToWindow) return
        editText.animate().cancel()
        editText.alpha = 0f
        editText.animate().alpha(1f).setDuration(TRANSCRIPT_FADE_MS).start()
    }

    /** Lets the field grow with its text up to [height]; the text scrolls beyond it */
    fun setMaxFieldHeight(height: Int) {
        val textHeight = height - FIELD_TEXT_TOP_MARGIN.dp.roundToInt()
        if (editText.maxHeight == textHeight) return
        editText.maxHeight = textHeight
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        onWindowFocusChanged?.invoke(hasWindowFocus)
    }

    /** Brings the keyboard back for a field that kept its focus */
    fun showInputKeyboard() {
        if (editText.hasFocus() && !dictationState.isActive) editText.showKeyboard()
    }

    fun setDraftText(text: String, focusInput: Boolean = true) {
        transcriptReveal.finish()
        if (dictationState.isActive) dictation?.cancel()
        editText.setText(text)
        editText.setSelection(editText.length())
        if (focusInput) focusInputWithKeyboard()
    }

    /** The field's text as it shows, for the sent question's bubble to grow out of */
    internal fun makeSentTextSource(): AgentSentMessageSource? =
        AgentSentMessageSource.makeText(editText, inputBackground)

    /**
     * The field, empty once its question has left it, fades back in over [durationMs], as
     * Telegram's does in its send transition
     */
    internal fun fadeInFieldText(durationMs: Long) {
        if (dictationState.isActive) return
        editText.animate().cancel()
        editText.alpha = 0f
        editText.animate().alpha(1f).setDuration(durationMs)
            .setInterpolator(LinearInterpolator()).start()
    }

    /** Gives the field the focus and the keyboard, with its draft as it is */
    fun focusInputWithKeyboard() {
        editText.requestFocus()
        editText.post {
            if (!dictationState.isActive && editText.hasFocus()) {
                editText.showKeyboard()
            }
        }
    }

    private fun isSoftKeyboardKey(event: KeyEvent): Boolean =
        (event.flags and KeyEvent.FLAG_SOFT_KEYBOARD) != 0 || event.device?.isVirtual != false

    private fun insertLineBreak() {
        val text = editText.text ?: return
        val start = max(0, min(editText.selectionStart, editText.selectionEnd))
        val end = max(editText.selectionStart, editText.selectionEnd).coerceAtLeast(start)
        text.replace(start, end, "\n")
    }

    private fun trySend() {
        if (dictationState.isActive) return
        transcriptReveal.finish()
        val text = editText.text?.toString()?.trim() ?: return
        if (text.isNotEmpty() && onSend?.invoke(text) == true) {
            editText.text?.clear()
        }
    }

    private fun updateSendButtonState() {
        val hasText = !editText.text.isNullOrBlank()
        isSendEnabled = isSubmissionEnabled && hasText
        applySendButtonTheme()
    }

    private var paddingAnimator: ValueAnimator? = null
    private var sideInsetAnimator: ValueAnimator? = null
    private var isKeyboardShown = false

    /**
     * Above the keyboard the field leaves 10 dp at its sides, otherwise 16 dp. With
     * [shouldFollowKeyboard] the keyboard's own motion moves the sides through [followKeyboard].
     */
    fun setKeyboardShown(isKeyboardUp: Boolean, shouldFollowKeyboard: Boolean = false) {
        if (isKeyboardShown == isKeyboardUp) return
        isKeyboardShown = isKeyboardUp
        sideInsetAnimator?.cancel()
        if (shouldFollowKeyboard) return
        val target = (if (isKeyboardUp) KEYBOARD_SIDE_INSET else IDLE_SIDE_INSET).dp
        sideInsetAnimator = ValueAnimator.ofInt(paddingStart, target).apply {
            duration = if (WGlobalStorage.getAreAnimationsActive()) SIDE_INSET_DURATION_MS else 0L
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation -> applySideInset(animation.animatedValue as Int) }
            start()
        }
    }

    /** Places the sides [openness] of the way from their resting inset (0) to the keyboard's (1) */
    fun followKeyboard(openness: Float) {
        sideInsetAnimator?.cancel()
        val idle = IDLE_SIDE_INSET.dp
        applySideInset(idle + ((KEYBOARD_SIDE_INSET.dp - idle) * openness).roundToInt())
    }

    private fun applySideInset(inset: Int) {
        if (paddingStart == inset && paddingEnd == inset) return
        setPaddingRelative(inset, paddingTop, inset, paddingBottom)
        onSideInsetChanged?.invoke(inset)
    }

    private fun applySendButtonTheme() {
        val buttons = agentComposerButtons(
            dictationState.phase,
            hasText = !editText.text.isNullOrBlank(),
            isAnswering = isAnswering
        )
        val shouldShowSend = buttons.isSendShown
        setSeparation(if (buttons.isCircleApart) 1f else 0f)
        setStopShown(buttons.isStopShown)
        val contentAlphaValue = (contentAlpha * 255).roundToInt()
        microphoneButton.setColorFilter(WColor.SecondaryText.color)
        (stopIcon.background as GradientDrawable).setColor(WColor.SecondaryText.color)
        applyStopProgress()
        val sendDrawable = GradientDrawable().apply {
            cornerRadius = 20f.dp
            if (isSendEnabled) {
                setColor(WColor.Tint.color)
            } else {
                setColor(WColor.SecondaryText.color.colorWithAlpha(DISABLED_SEND_FILL_ALPHA))
            }
            alpha = contentAlphaValue
        }
        sendButton.background = sendDrawable
        sendButton.imageAlpha = contentAlphaValue

        sendButton.setImageResource(R.drawable.ic_send)
        sendButton.setColorFilter(
            if (isSendEnabled) WColor.TextOnTint.color else WColor.SecondaryText.color
        )
        sendButton.isEnabled = isSendEnabled
        sendButton.isClickable = isSendEnabled
        if (isSendShown == shouldShowSend) return
        isSendShown = shouldShowSend
        if (shouldShowSend) {
            sendButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            sendButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
        animateInputPadding()
    }

    private fun setSeparation(target: Float) {
        if (separationTarget == target) return
        separationTarget = target
        separationAnimator?.cancel()
        separationAnimator = null
        if (!isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            applySeparation(target)
            return
        }
        separationAnimator = ValueAnimator.ofFloat(separation, target).apply {
            duration = SEPARATION_MS
            interpolator = TELEGRAM_CURVE
            addUpdateListener { applySeparation(it.animatedValue as Float) }
            start()
        }
    }

    // The field gives the circle its room as it stands apart, and takes it back as the circle merges into its end
    private fun applySeparation(value: Float) {
        separation = value
        val reserve = ((MICROPHONE_SIZE + MICROPHONE_GAP).dp * value).roundToInt()
        val backgroundParams = inputBackground.layoutParams as LayoutParams
        if (backgroundParams.marginEnd != reserve) {
            backgroundParams.marginEnd = reserve
            inputBackground.layoutParams = backgroundParams
        }
        applyMicrophoneCircle()
    }

    private fun applyMicrophoneCircle() {
        val merge = MERGED_MICROPHONE_SCALE + (1 - MERGED_MICROPHONE_SCALE) * separation
        val grow = hostedGrowFrom + (1 - hostedGrowFrom) * hostedAppearance
        microphoneCircle.alpha = separation * hostedAppearance * (1 - recordingCover)
        microphoneCircle.scaleX = merge * hostedSwell
        microphoneCircle.scaleY = merge * hostedSwell
        // It merges toward the field's end
        microphoneCircle.translationX =
            -(1 - separation) * MICROPHONE_GAP.dp * LocaleController.rtlMultiplier
        microphoneButton.scaleX = grow
        microphoneButton.scaleY = grow
        val isShown = separation > 0f && hostedAppearance > 0f
        microphoneCircle.visibility = if (isShown) VISIBLE else INVISIBLE
    }

    /**
     * Grows the field and the microphone's circle out of a host's own pieces: [appearance] fades them in, the field
     * widening from [growFrom] of its width toward the circle and the microphone growing in its circle as much, and
     * both swell by [swell]. 1, 1, 1 shows them as they are.
     */
    fun setHostedMorph(appearance: Float, swell: Float, growFrom: Float) {
        hostedAppearance = appearance
        hostedSwell = swell
        hostedGrowFrom = growFrom
        inputBackground.alpha = appearance
        inputBackground.pivotX = if (LocaleController.isRTL) 0f else inputBackground.width.toFloat()
        inputBackground.pivotY = inputBackground.height / 2f
        inputBackground.scaleX = swell * (growFrom + (1 - growFrom) * appearance)
        inputBackground.scaleY = swell
        followField()
        applyMicrophoneCircle()
    }

    // The rim lies round the field, where the field is in the window, and takes its morph about the same point
    private fun followField() {
        val host = rimHost ?: return
        val margin = AGENT_FIELD_RIM_MARGIN.dp.roundToInt()
        getLocationInWindow(rimLocation)
        host.getLocationInWindow(rimHostLocation)
        val left = rimLocation[0] - rimHostLocation[0] + inputBackground.left - margin
        val top = rimLocation[1] - rimHostLocation[1] + inputBackground.top - margin
        val right = left + inputBackground.width + 2 * margin
        val bottom = top + inputBackground.height + 2 * margin
        if (fieldRim.left != left || fieldRim.top != top || fieldRim.right != right ||
            fieldRim.bottom != bottom
        ) {
            fieldRim.layout(left, top, right, bottom)
        }
        fieldRim.isInvisible = !inputBackground.isShown
        fieldRim.alpha = alpha * inputBackground.alpha
        fieldRim.pivotX = inputBackground.pivotX + margin
        fieldRim.pivotY = inputBackground.pivotY + margin
        fieldRim.scaleX = inputBackground.scaleX
        fieldRim.scaleY = inputBackground.scaleY
        fieldRim.translationX = inputBackground.translationX
        fieldRim.translationY = inputBackground.translationY
    }

    // The field glows while a question is recognised and until its transcript has come in, never while recording
    private fun updateGlow() {
        val isGlowing = dictationState.phase == AgentDictationPhase.RECOGNIZING ||
            transcriptReveal.isRunning
        if (isGlowing) followField()
        fieldGlow.setGlowing(isGlowing)
        fieldRim.setGlowing(isGlowing)
    }

    private fun animateInputPadding() {
        paddingAnimator?.cancel()
        val targetPadding = if (isSendShown == true) 52.dp else 16.dp
        paddingAnimator = ValueAnimator.ofInt(editText.paddingEnd, targetPadding).apply {
            duration = if (WGlobalStorage.getAreAnimationsActive()) {
                AnimationConstants.SUPER_QUICK_ANIMATION
            } else {
                0L
            }
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                editText.setPaddingRelative(
                    editText.paddingStart,
                    editText.paddingTop,
                    animation.animatedValue as Int,
                    editText.paddingBottom
                )
            }
            start()
        }
    }

    fun setSubmissionEnabled(enabled: Boolean) {
        if (isSubmissionEnabled == enabled) return
        isSubmissionEnabled = enabled
        microphoneButton.isEnabled = enabled || isStopShown
        updateSendButtonState()
    }

    // The microphone morphs into Stop and back: one fades and shrinks as the other grows in
    private fun setStopShown(shown: Boolean) {
        if (isStopShown == shown) return
        isStopShown = shown
        microphoneButton.isEnabled = isSubmissionEnabled || shown
        updateMicrophoneDescription()
        stopAnimator?.cancel()
        val target = if (shown) 1f else 0f
        // Out of sight, merged into the field, the circle takes its icon at once, so it comes back with it
        if (!isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive() ||
            microphoneCircle.visibility != VISIBLE
        ) {
            stopProgress = target
            applyStopProgress()
            return
        }
        stopAnimator = ValueAnimator.ofFloat(stopProgress, target).apply {
            duration = STOP_MORPH_MS
            interpolator = TELEGRAM_CURVE
            addUpdateListener {
                stopProgress = it.animatedValue as Float
                applyStopProgress()
            }
            start()
        }
    }

    private fun applyStopProgress() {
        microphoneButton.imageAlpha = (contentAlpha * 255 * (1 - stopProgress)).roundToInt()
        stopIcon.alpha = contentAlpha * stopProgress
        stopIcon.visibility = if (stopProgress > 0f) VISIBLE else INVISIBLE
        val scale = STOP_START_SCALE + (1 - STOP_START_SCALE) * stopProgress
        stopIcon.scaleX = scale
        stopIcon.scaleY = scale
    }

    private fun updateMicrophoneDescription() {
        val state = dictationState
        val isFinishing = state.phase == AgentDictationPhase.RECORDING && state.locked
        microphoneButton.contentDescription = LocaleController.getString(
            when {
                isStopShown -> "\$agent_stop_answer"
                isFinishing -> "\$agent_dictation_finish"
                else -> "\$agent_dictation_start"
            }
        )
    }

    internal fun bindDictation(controller: AgentDictationController) {
        dictation = controller
        renderDictation(controller.state)
    }

    internal fun renderDictation(state: AgentDictationState) {
        val previous = dictationState
        dictationState = state
        val isRecording = state.phase == AgentDictationPhase.RECORDING
        val showsStrip = isRecording || state.phase == AgentDictationPhase.RECOGNIZING
        if (state.isActive) transcriptReveal.finish()
        updateGlow()
        val hasBeenShowingStrip = previous.phase == AgentDictationPhase.RECORDING ||
            previous.phase == AgentDictationPhase.RECOGNIZING
        if (showsStrip != hasBeenShowingStrip) fadeDraft(isDraftVisible = !showsStrip)
        editText.importantForAccessibility = if (showsStrip) {
            IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        } else {
            IMPORTANT_FOR_ACCESSIBILITY_AUTO
        }
        recordingStrip.visibility = if (showsStrip) VISIBLE else GONE
        recordingStrip.render(state)
        recordingCircle.update(state)
        updateMicrophoneDescription()
        // A recording slid away to cancel keeps the finger's drag, so the rest of it doesn't start a swipe back
        if (!state.isActive && !isMicrophoneGesture) {
            parent?.requestDisallowInterceptTouchEvent(false)
        }
        applySendButtonTheme()
        moveAccessibilityFocus(previous, state)
        updateFieldInUse()
    }

    private fun updateFieldInUse() {
        val isInUse =
            isAgentFieldInUse(dictationState.phase, hasDraft = !editText.text.isNullOrBlank())
        if (isInUse == isFieldInUse) return
        isFieldInUse = isInUse
        onFieldInUseChanged?.invoke(isInUse)
    }

    // The field's text fades out under the recording, as the placeholder does in Telegram
    private fun fadeDraft(isDraftVisible: Boolean) {
        editText.animate().cancel()
        if (isDraftVisible || !isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            editText.alpha = if (isDraftVisible) 1f else 0f
            return
        }
        editText.animate().alpha(0f).setDuration(DRAFT_FADE_MS).setInterpolator(TELEGRAM_CURVE)
            .start()
    }

    // Locked, TalkBack goes to the microphone that finishes; recognizing, to the strip's Cancel;
    // back from recognizing, to the field
    private fun moveAccessibilityFocus(previous: AgentDictationState, state: AgentDictationState) {
        if (!isAccessibilityEnabled()) return
        val hasBeenLocked = previous.phase == AgentDictationPhase.RECORDING && previous.locked
        val target = when {
            state.phase == AgentDictationPhase.RECORDING && state.locked && !hasBeenLocked ->
                microphoneButton

            state.phase == AgentDictationPhase.RECOGNIZING &&
                previous.phase != AgentDictationPhase.RECOGNIZING -> recordingStrip.cancelView

            state.phase == AgentDictationPhase.IDLE &&
                previous.phase == AgentDictationPhase.RECOGNIZING -> editText

            else -> null
        } ?: return
        val focus = AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS
        post { target.performAccessibilityAction(focus, null) }
    }

    /** A recording produced no transcript: the circle turns red, and TalkBack hears why */
    internal fun showDictationFailure(failure: AgentDictationFailure) {
        Haptics.play(this, HapticType.ERROR)
        if (isAccessibilityEnabled()) {
            @Suppress("DEPRECATION")
            announceForAccessibility(getAgentDictationFailureText(failure))
        }
    }

    private fun isAccessibilityEnabled(): Boolean =
        (context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)
            ?.isEnabled == true

    private fun isTouchExplorationEnabled(): Boolean =
        (context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)
            ?.isTouchExplorationEnabled == true

    private fun acquireScrollLocks(): Boolean {
        var ancestor = parent
        while (ancestor is View) {
            if (ancestor is ScrollLockHost) {
                val release = ancestor.acquireScrollLock()
                if (release == null) {
                    releaseScrollLocks()
                    return false
                }
                scrollLockReleases.add(release)
            }
            ancestor = ancestor.parent
        }
        return true
    }

    private fun releaseScrollLocks() {
        scrollLockReleases.forEach { it() }
        scrollLockReleases.clear()
    }

    // Telegram's recording gesture on the microphone: hold to record, slide toward the start to
    // cancel, slide up to lock, let go to transcribe
    private fun handleMicrophoneTouch(event: MotionEvent): Boolean {
        if (isTouchExplorationEnabled() || isStopShown) return false
        val isOwnGesture = isMicrophoneGesture
        val density = resources.displayMetrics.density
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val phase = dictationState.phase
                if (phase != AgentDictationPhase.IDLE && phase != AgentDictationPhase.FAILED) {
                    return false
                }
                if (shouldHoldDictation?.invoke() == true) return true
                if (!acquireScrollLocks()) return false
                isMicrophoneGesture = true
                touchStartX = event.rawX
                touchStartY = event.rawY
                microphoneVelocity?.recycle()
                microphoneVelocity = VelocityTracker.obtain().apply { addMovement(event) }
                parent?.requestDisallowInterceptTouchEvent(true)
                dictation?.press()
            }

            MotionEvent.ACTION_MOVE -> if (isMicrophoneGesture) {
                microphoneVelocity?.addMovement(event)
                dictation?.move(
                    horizontalDp = (event.rawX - touchStartX) / density,
                    upDp = (touchStartY - event.rawY) / density,
                    cancelDirection = cancelDirection
                )
            }

            MotionEvent.ACTION_UP -> if (isMicrophoneGesture) {
                val tracker = microphoneVelocity
                tracker?.addMovement(event)
                tracker?.computeCurrentVelocity(MILLISECONDS_PER_SECOND)
                val horizontalVelocity = (tracker?.xVelocity ?: 0f) / density
                val upVelocity = -(tracker?.yVelocity ?: 0f) / density
                endMicrophoneGesture()
                dictation?.release(
                    horizontalDp = (event.rawX - touchStartX) / density,
                    upDp = (touchStartY - event.rawY) / density,
                    horizontalVelocity = horizontalVelocity,
                    upVelocity = upVelocity,
                    cancelDirection = cancelDirection
                )
                isGestureEndClick = true
                try {
                    microphoneButton.performClick()
                } finally {
                    isGestureEndClick = false
                }
            }

            MotionEvent.ACTION_CANCEL -> if (isMicrophoneGesture) {
                endMicrophoneGesture()
                if (!dictationState.locked) dictation?.cancel()
            }
        }
        // A tap outside a hold, as on a locked recording's checkmark, goes on to the button's click
        return isOwnGesture || isMicrophoneGesture
    }

    private fun endMicrophoneGesture() {
        isMicrophoneGesture = false
        microphoneVelocity?.recycle()
        microphoneVelocity = null
        releaseScrollLocks()
        parent?.requestDisallowInterceptTouchEvent(false)
    }

    private fun applyContentColors() {
        val alpha = (contentAlpha * 255).roundToInt()
        editText.setHintTextColor(WColor.SecondaryText.color.colorWithAlpha(alpha))
        editText.setTextColor(WColor.PrimaryText.color.colorWithAlpha(alpha))
    }

    override fun updateTheme() {
        applyContentColors()
        editText.highlightColor = WColor.Tint.color and 0x40FFFFFF

        inputBackground.setBackgroundColor(
            Color.TRANSPARENT,
            24f.dp,
            clipToBounds = true
        )
        inputGlass?.updateTheme()
        microphoneGlass?.updateTheme()

        recordingCircle.updateTheme()
        recordingStrip.updateTheme()
        fieldGlow.updateTheme()
        fieldRim.updateTheme()

        applySendButtonTheme()
        animateInputPadding()
    }
}

/**
 * The field records, recognizes or holds a draft, so the chat list's search makes way for it, as Telegram's attach
 * button does for a recording
 */
internal fun isAgentFieldInUse(phase: AgentDictationPhase, hasDraft: Boolean): Boolean =
    hasDraft || phase == AgentDictationPhase.RECORDING || phase == AgentDictationPhase.RECOGNIZING

internal enum class AgentComposerButton {
    SEND,
    STOP,
    MICROPHONE
}

/** The button at the field's end: send for a draft, else Stop while the Agent answers, else the microphone */
internal fun resolveAgentComposerButton(hasText: Boolean, isAnswering: Boolean) = when {
    hasText -> AgentComposerButton.SEND
    isAnswering -> AgentComposerButton.STOP
    else -> AgentComposerButton.MICROPHONE
}

/** What the composer's buttons show: the send button at the field's end, and the circle beside the field */
internal data class AgentComposerButtons(
    val isSendShown: Boolean,
    /** The circle stands apart from the field; otherwise it is merged into the field's end */
    val isCircleApart: Boolean,
    /** The circle holds Stop in place of the microphone */
    val isStopShown: Boolean
)

internal fun agentComposerButtons(
    phase: AgentDictationPhase,
    hasText: Boolean,
    isAnswering: Boolean
): AgentComposerButtons {
    val isIdle = phase == AgentDictationPhase.IDLE || phase == AgentDictationPhase.PRESSING ||
        phase == AgentDictationPhase.FAILED
    val button = resolveAgentComposerButton(hasText, isAnswering)
    return AgentComposerButtons(
        // A draft keeps its send button; it greys out while the Agent can't take the question. The microphone stays
        // under the recording circle, whose checkmark finishes a locked recording.
        isSendShown = isIdle && button == AgentComposerButton.SEND,
        // The circle, with the microphone or Stop, stands apart while the field is empty and while recording; it
        // merges into the field while the field has text, where the send button is, and while recognizing, when the
        // strip spans it
        isCircleApart = (isIdle && button != AgentComposerButton.SEND) ||
            phase == AgentDictationPhase.RECORDING,
        // While an answer is being written, the circle keeps Stop as a draft merges it into the field and as clearing
        // the draft brings it back, so the draft trades Stop for the send button directly
        isStopShown = isAnswering &&
            (phase == AgentDictationPhase.IDLE || phase == AgentDictationPhase.FAILED)
    )
}
