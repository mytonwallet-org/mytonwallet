package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
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
import androidx.core.view.updateLayoutParams
import androidx.core.widget.doAfterTextChanged
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationCancelDirection
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationFailure
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationHoldZone
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationState
import org.mytonwallet.app_air.uiagent.agentV2.filterDraftEdit
import org.mytonwallet.app_air.uiagent.agentV2.getAgentDictationFailureText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_COMPOSER_FIELD_BOTTOM
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

// The strip keeps this far from the field's start
private const val STRIP_INSET = 16

// The support circle beside the chat list's empty field, and the gap between them, as the microphone's was
private const val SUPPORT_CIRCLE_SIZE = 48
private const val SUPPORT_CIRCLE_GAP = 12

// The support circle's headset while support can't be called, as dim as the web's disabled headset
private const val DISABLED_SUPPORT_ALPHA = 0.4f

// The buttons inside the field, as in Claude's: 40 dp, 4 dp inside its end, the microphone 4 dp before the send button
// or Stop
private const val FIELD_BUTTON_SIZE = 40
private const val FIELD_BUTTON_INSET = 4
private const val FIELD_TEXT_END_INSET = 16
private const val FIELD_TEXT_BUTTON_GAP = 8
private const val STOP_SIZE = 12
private const val STOP_RADIUS = 2.5f

// The circle shrinks this far as it merges into the field's end
private const val MERGED_CIRCLE_SCALE = 0.6f
private const val SEPARATION_MS = 400L
private const val DRAFT_FADE_MS = 400L

// The draft's bottom padding, and the room under it for the recording's row, as tall as the row
private const val DRAFT_BOTTOM_PADDING = 10
private const val DRAFT_ROW_ROOM = 48
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

    /** Called by Stop, which stands in the send button's place while the Agent answers */
    var onStop: (() -> Unit)? = null

    /** Called by the support circle beside the field */
    var onSupport: (() -> Unit)? = null

    /** The support circle stands beside the empty field, as the chat list's once it has chats */
    var isSupportOffered = false
        set(value) {
            if (field == value) return
            field = value
            applySendButtonTheme()
        }

    /** The offered support circle is grey and does nothing while support can't be called, as on iOS and the web */
    var isSupportEnabled = true
        set(value) {
            if (field == value) return
            field = value
            applySendButtonTheme()
            applySupportCircle()
        }

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
        setPaddingRelative(16.dp, 10.dp, 16.dp, DRAFT_BOTTOM_PADDING.dp)
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

    // The recording's cross at the field's start, across the field from Send: tapped, or reached by the
    // held microphone, it cancels the recording
    private val recordingCancelButton = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER
        setImageResource(org.mytonwallet.app_air.uiagent.R.drawable.ic_agent_dictation_cancel)
        contentDescription = LocaleController.getString("Cancel")
        isClickable = true
        isFocusable = true
        scaleX = 0f
        scaleY = 0f
        visibility = GONE
    }
    private var isRecordingCancelShown = false

    /** A chat's field keeps Send in place, quiet while there is nothing to send, so the microphone stays put */
    var isSendAlwaysShown = false
        set(value) {
            if (field == value) return
            field = value
            applySendButtonTheme()
        }

    // The microphone inside the field, as in Claude's: at the field's end, stepping aside for the send button or Stop
    private val microphoneButton = ImageView(context).apply {
        id = UIComponentsR.id.agent_microphone
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_dictation_start")
        setImageResource(org.mytonwallet.app_air.uiagent.R.drawable.ic_agent_microphone)
    }
    private var isMicrophoneShifted = false
    private var isMicrophoneShown = true

    // While an answer is being written, Stop stands in the send button's place: a filled square, as in ChatGPT's and
    // Telegram's stop states. UI automation finds Stop by its id while it shows.
    private val stopIcon = View(context).apply {
        background = GradientDrawable().apply { cornerRadius = STOP_RADIUS.dp }
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val stopButton = WFrameLayout(context).apply {
        id = UIComponentsR.id.agent_stop
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_stop_answer")
        scaleX = 0f
        scaleY = 0f
        visibility = INVISIBLE
        addView(stopIcon, LayoutParams(STOP_SIZE.dp, STOP_SIZE.dp, Gravity.CENTER))
    }
    private var isStopShown = false

    // The headset in its glass circle beside the chat list's empty field, which merges into the field for a draft
    private val supportButton = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_support_contact")
        setImageResource(org.mytonwallet.app_air.uiagent.R.drawable.ic_agent_composer_support)
    }
    private val supportCircle = WFrameLayout(context).apply {
        addView(supportButton, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private var supportGlass: WGlassView? = null

    // 1 while the support circle stands apart from the field, 0 while merged into its end
    private var separation = 0f
    private var separationTarget = 0f
    private var separationAnimator: ValueAnimator? = null

    // A host's morph of the field and the circle out of its own pieces; see [setHostedMorph]
    private var hostedAppearance = 1f
    private var hostedSwell = 1f
    private var hostedGrowFrom = 1f

    // How far the support circle has slid off past the field's end, as the field widens over its place
    private var supportSlide = 0f
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
        onHostResized = { layoutRecording(dictationState) }
        onCoverChanged = { cover ->
            recordingCover = cover
            applyMicrophoneAlpha()
        }
        onStop = {
            if (dictationState.phase == AgentDictationPhase.RECORDING && dictationState.locked) {
                dictation?.finish()
            }
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
        setPaddingDp(
            IDLE_SIDE_INSET,
            AGENT_COMPOSER_FIELD_TOP,
            IDLE_SIDE_INSET,
            AGENT_COMPOSER_FIELD_BOTTOM
        )
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

        for (button in listOf(microphoneButton, sendButton, stopButton)) {
            inputBackground.addView(
                button,
                LayoutParams(FIELD_BUTTON_SIZE.dp, FIELD_BUTTON_SIZE.dp).apply {
                    gravity = Gravity.END or Gravity.BOTTOM
                    marginEnd = FIELD_BUTTON_INSET.dp
                    bottomMargin = FIELD_BUTTON_INSET.dp
                }
            )
        }
        // The strip spans the field from the cross up to the microphone, which the recording circle covers
        inputBackground.addView(
            recordingStrip,
            LayoutParams(MATCH_PARENT, 48.dp).apply {
                gravity = Gravity.BOTTOM
                marginStart = STRIP_INSET.dp
                marginEnd = (FIELD_BUTTON_INSET + FIELD_BUTTON_SIZE + FIELD_TEXT_BUTTON_GAP).dp
            }
        )
        inputBackground.addView(
            recordingCancelButton,
            LayoutParams(FIELD_BUTTON_SIZE.dp, FIELD_BUTTON_SIZE.dp).apply {
                gravity = Gravity.START or Gravity.BOTTOM
                marginStart = FIELD_BUTTON_INSET.dp
                bottomMargin = FIELD_BUTTON_INSET.dp
            }
        )

        addView(inputBackground, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            supportCircle,
            LayoutParams(SUPPORT_CIRCLE_SIZE.dp, SUPPORT_CIRCLE_SIZE.dp).apply {
                gravity = Gravity.END or Gravity.BOTTOM
            }
        )
        inputGlass = WGlassView.attachTo(
            inputBackground,
            24f.dp,
            GlassProviders.composer(WColor.SearchFieldBackground),
            blurRootView
        )
        supportGlass = WGlassView.attachTo(
            supportCircle,
            (SUPPORT_CIRCLE_SIZE / 2f).dp,
            GlassProviders.composer(WColor.SearchFieldBackground),
            blurRootView
        )
        applySupportCircle()

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

        sendButton.setOnClickListener { handleSendClick() }
        recordingCancelButton.setOnClickListener {
            if (isRecordingCancelShown) dictation?.cancel()
        }
        // A tap on the microphone, or a click with TalkBack, starts a hands-free recording, which
        // finishes from the stop over the microphone, or from the microphone with TalkBack. The click
        // that ends a hold does neither.
        microphoneButton.setOnClickListener {
            if (isGestureEndClick) return@setOnClickListener
            val state = dictationState
            if (state.phase == AgentDictationPhase.RECORDING && state.locked) {
                dictation?.finish()
            } else if (shouldHoldDictation?.invoke() != true) {
                dictation?.startHandsFree()
            }
        }
        microphoneButton.setOnTouchListener { _, event -> handleMicrophoneTouch(event) }
        stopButton.setOnClickListener { onStop?.invoke() }
        supportButton.setOnClickListener { onSupport?.invoke() }

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
        draftRoomAnimator?.end()
        transcriptReveal.finish()
        recordingCircle.detach()
        endMicrophoneGesture()
        viewTreeObserver.removeOnPreDrawListener(rimFollower)
        rimHost?.overlay?.remove(fieldRim)
        rimHost = null
        super.onDetachedFromWindow()
    }

    /**
     * Puts a transcript into the field after its draft character by character, each out of a blur, as iOS does. Without
     * motion, and for TalkBack, which reads the field as it comes, the whole text fades in.
     */
    internal fun setDictationText(text: String) {
        val areAnimatorsEnabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ValueAnimator.areAnimatorsEnabled()
        val canReveal = isAttachedToWindow && WGlobalStorage.getAreAnimationsActive() &&
            areAnimatorsEnabled && !isAccessibilityEnabled()
        if (canReveal) {
            transcriptReveal.start(text)
            updateGlow()
            return
        }
        val draft = editText.text?.toString().orEmpty()
        setDraftText(getAgentDictationPrefix(draft) + text, focusInput = false)
        if (!isAttachedToWindow) return
        editText.animate().cancel()
        editText.alpha = 0f
        editText.animate().alpha(1f).setDuration(TRANSCRIPT_FADE_MS).start()
    }

    /** Sends a transcript at once, after the draft's text, as Send does */
    internal fun sendDictationText(text: String) {
        transcriptReveal.finish()
        sendAgentDictationText(
            draft = editText.text?.toString().orEmpty(),
            text = text,
            onDraftChanged = { setDraftText(it, focusInput = false) },
            onSend = onSend
        )
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

    /** Send during a hands-free recording stops it, and its transcript goes as the question */
    private fun handleSendClick() {
        if (dictationState.phase == AgentDictationPhase.RECORDING && dictationState.locked) {
            // While sending is blocked, as by a limit reached during the recording, the transcript goes to the draft
            dictation?.finish(isSending = isSubmissionEnabled)
            return
        }
        trySend()
    }

    /** The keyboard's Return and send action leave a recording going, as on the web */
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
    private var draftRoomAnimator: ValueAnimator? = null
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
            isAnswering = isAnswering,
            isSupportOffered = isSupportOffered,
            isSendAlwaysShown = isSendAlwaysShown
        )
        val isRecording = dictationState.phase == AgentDictationPhase.RECORDING
        // Send is accented when it would send: with text, for a recording once it has heard something to recognize,
        // and for the held microphone over Send
        val isSendAccented = if (isRecording) {
            (!dictationState.locked && dictationState.holdZone == AgentDictationHoldZone.SEND) ||
                dictationState.hasSpeech
        } else {
            isSendEnabled
        }
        setRecordingCancelShown(isRecording)
        val isCancelHighlighted = isRecording && !dictationState.locked &&
            dictationState.holdZone == AgentDictationHoldZone.CANCEL
        recordingCancelButton.background = GradientDrawable().apply {
            cornerRadius = 20f.dp
            setColor(
                if (isCancelHighlighted) {
                    WColor.Red.color
                } else {
                    WColor.SecondaryText.color.colorWithAlpha(DISABLED_SEND_FILL_ALPHA)
                }
            )
        }
        recordingCancelButton.setColorFilter(
            if (isCancelHighlighted) WColor.TextOnTint.color else WColor.PrimaryText.color
        )
        val shouldShowSend = buttons.isSendShown
        setSeparation(if (buttons.isCircleApart) 1f else 0f)
        setStopShown(buttons.isStopShown)
        setMicrophoneShown(buttons.isMicrophoneShown)
        setMicrophoneShifted(buttons.isSendShown || buttons.isStopShown)
        val contentAlphaValue = (contentAlpha * 255).roundToInt()
        // The field's microphone is gray, so the field's text leads
        microphoneButton.setColorFilter(WColor.SecondaryText.color)
        microphoneButton.imageAlpha = contentAlphaValue
        supportButton.setColorFilter(WColor.SecondaryText.color)
        val supportAlpha = contentAlpha * if (isSupportEnabled) 1f else DISABLED_SUPPORT_ALPHA
        supportButton.imageAlpha = (supportAlpha * 255).roundToInt()
        stopButton.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(WColor.Tint.color)
            alpha = contentAlphaValue
        }
        (stopIcon.background as GradientDrawable).setColor(WColor.TextOnTint.color)
        stopIcon.alpha = contentAlpha
        val sendDrawable = GradientDrawable().apply {
            cornerRadius = 20f.dp
            if (isSendAccented) {
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
            if (isSendAccented) WColor.TextOnTint.color else WColor.SecondaryText.color
        )
        val canSend = isSendEnabled || (isRecording && dictationState.locked && isSubmissionEnabled)
        sendButton.isEnabled = canSend
        sendButton.isClickable = canSend
        if (isSendShown == shouldShowSend) return
        isSendShown = shouldShowSend
        if (shouldShowSend) {
            sendButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            sendButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
        animateInputPadding()
    }

    // The cross grows in at the field's start as Send does at its end, and the strip makes room for it
    private fun setRecordingCancelShown(isShown: Boolean) {
        if (isRecordingCancelShown == isShown) return
        isRecordingCancelShown = isShown
        // Set through the layout params, so the start margin is resolved again
        recordingStrip.updateLayoutParams<LayoutParams> {
            marginStart = if (isShown) {
                (FIELD_BUTTON_INSET + FIELD_BUTTON_SIZE + FIELD_TEXT_BUTTON_GAP).dp
            } else {
                STRIP_INSET.dp
            }
        }
        if (isShown) {
            recordingCancelButton.visibility = VISIBLE
            recordingCancelButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            recordingCancelButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION) {
                if (!isRecordingCancelShown) recordingCancelButton.visibility = GONE
            }
        }
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
        val circleRoom = (SUPPORT_CIRCLE_SIZE + SUPPORT_CIRCLE_GAP).dp
        val reserve = (circleRoom * value * (1 - supportSlide)).roundToInt()
        val backgroundParams = inputBackground.layoutParams as LayoutParams
        if (backgroundParams.marginEnd != reserve) {
            backgroundParams.marginEnd = reserve
            inputBackground.layoutParams = backgroundParams
        }
        applySupportCircle()
    }

    private fun applySupportCircle() {
        val merge = MERGED_CIRCLE_SCALE + (1 - MERGED_CIRCLE_SCALE) * separation
        val grow = hostedGrowFrom + (1 - hostedGrowFrom) * hostedAppearance
        supportCircle.alpha = separation * hostedAppearance * (1 - supportSlide)
        supportCircle.scaleX = merge * hostedSwell
        supportCircle.scaleY = merge * hostedSwell
        // It merges toward the field's end, or slides off past it
        val slideTravel = (SUPPORT_CIRCLE_SIZE.dp + paddingEnd) * supportSlide
        val mergeTravel = (1 - separation) * SUPPORT_CIRCLE_GAP.dp
        supportCircle.translationX = (slideTravel - mergeTravel) * LocaleController.rtlMultiplier
        supportButton.scaleX = grow
        supportButton.scaleY = grow
        val isShown = separation > 0f && hostedAppearance > 0f && supportSlide < 1f
        supportCircle.visibility = if (isShown) VISIBLE else INVISIBLE
        supportButton.isEnabled = separationTarget == 1f && isSupportEnabled && supportSlide < 0.5f
    }

    // The microphone gives way to the recognition's strip, and under the recording circle shows only what the circle
    // leaves of it
    private fun setMicrophoneShown(shown: Boolean) {
        if (isMicrophoneShown == shown) return
        isMicrophoneShown = shown
        microphoneButton.isEnabled = shown && isSubmissionEnabled
        applyMicrophoneAlpha()
    }

    private fun applyMicrophoneAlpha() {
        microphoneButton.alpha = if (isMicrophoneShown) 1 - recordingCover else 0f
    }

    // The microphone steps aside for the send button or Stop at the field's end, and back
    private fun setMicrophoneShifted(shifted: Boolean) {
        if (isMicrophoneShifted == shifted) return
        isMicrophoneShifted = shifted
        val target = if (shifted) {
            -(FIELD_BUTTON_SIZE + FIELD_BUTTON_INSET).dp.toFloat() * LocaleController.rtlMultiplier
        } else {
            0f
        }
        microphoneButton.animate().cancel()
        if (!isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            microphoneButton.translationX = target
            return
        }
        microphoneButton.animate()
            .translationX(target)
            .setDuration(AnimationConstants.SUPER_QUICK_ANIMATION)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .start()
        animateInputPadding()
    }

    /**
     * Slides the support circle off past the field's end by [progress], 0 to 1, as the field widens over its place, the
     * way the chat list's search circle slides off past its start
     */
    fun setSupportSlide(progress: Float) {
        if (supportSlide == progress) return
        supportSlide = progress
        applySeparation(separation)
    }

    /**
     * Grows the field and the support circle out of a host's own pieces: [appearance] fades them in, the field widening
     * from [growFrom] of its width toward the circle and the headset growing in its circle as much, and both swell by
     * [swell]. 1, 1, 1 shows them as they are.
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
        applySupportCircle()
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

    // The text keeps clear of the buttons at the field's end: the microphone, and the send button or Stop beside it
    private fun animateInputPadding() {
        paddingAnimator?.cancel()
        val buttonCount = (if (isMicrophoneShown) 1 else 0) +
            (if (isSendShown == true || isStopShown) 1 else 0)
        val targetPadding = if (buttonCount == 0) {
            FIELD_TEXT_END_INSET.dp
        } else {
            (buttonCount * (FIELD_BUTTON_SIZE + FIELD_BUTTON_INSET) + FIELD_TEXT_BUTTON_GAP).dp
        }
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
        microphoneButton.isEnabled = enabled && isMicrophoneShown
        updateSendButtonState()
    }

    // Stop grows in at the field's end as the send button does, and shrinks away
    private fun setStopShown(shown: Boolean) {
        if (isStopShown == shown) return
        isStopShown = shown
        stopButton.isEnabled = shown
        stopButton.importantForAccessibility =
            if (shown) IMPORTANT_FOR_ACCESSIBILITY_YES else IMPORTANT_FOR_ACCESSIBILITY_NO
        if (!isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            stopButton.scaleX = if (shown) 1f else 0f
            stopButton.scaleY = stopButton.scaleX
            stopButton.visibility = if (shown) VISIBLE else INVISIBLE
        } else if (shown) {
            stopButton.visibility = VISIBLE
            stopButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            stopButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
        animateInputPadding()
    }

    // Where the circle travels and rests in the field as it is laid out now, and where the strip meets it
    private fun layoutRecording(state: AgentDictationState) {
        val fieldButtonCentre = (FIELD_BUTTON_INSET + FIELD_BUTTON_SIZE / 2).dp.toFloat()
        recordingCircle.setTravelBounds(
            cross = fieldButtonCentre,
            send = inputBackground.width - fieldButtonCentre,
            sendClearance = (FIELD_BUTTON_SIZE + FIELD_BUTTON_INSET).dp.toFloat()
        )
        recordingCircle.update(state)
        // The strip's hint keeps clear of the circle, and a hands-free recording's thread comes out of its stop
        recordingStrip.stopCenter = recordingCircle.restingDistance -
            (FIELD_BUTTON_INSET + FIELD_BUTTON_SIZE + FIELD_TEXT_BUTTON_GAP).dp
    }

    private fun updateMicrophoneDescription() {
        val state = dictationState
        val isFinishing = state.phase == AgentDictationPhase.RECORDING && state.locked
        microphoneButton.contentDescription = LocaleController.getString(
            if (isFinishing) "\$agent_dictation_finish" else "\$agent_dictation_start"
        )
    }

    internal fun bindDictation(controller: AgentDictationController) {
        dictation = controller
        renderDictation(controller.state)
    }

    internal fun renderDictation(state: AgentDictationState) {
        val previous = dictationState
        dictationState = state
        // A recording that ends under the finger, as at its limit, disables the microphone, which then never hears the
        // finger lift: the hold ends here
        if (state.phase == AgentDictationPhase.RECOGNIZING && isMicrophoneGesture) {
            endMicrophoneGesture()
        }
        val isRecording = state.phase == AgentDictationPhase.RECORDING
        val showsStrip = isRecording || state.phase == AgentDictationPhase.RECOGNIZING
        if (state.isActive) transcriptReveal.finish()
        updateGlow()
        val hasBeenShowingStrip = previous.phase == AgentDictationPhase.RECORDING ||
            previous.phase == AgentDictationPhase.RECOGNIZING
        if (showsStrip != hasBeenShowingStrip) {
            // With a draft, the recording's row goes under it, as on iOS: the draft stays, and the field grows by
            // the row
            val isUnderDraft = showsStrip && !editText.text.isNullOrBlank()
            fadeDraft(isDraftVisible = !showsStrip || isUnderDraft)
            setDraftRowRoom(isUnderDraft)
        }
        editText.importantForAccessibility = if (showsStrip) {
            IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        } else {
            IMPORTANT_FOR_ACCESSIBILITY_AUTO
        }
        layoutRecording(state)
        recordingStrip.visibility = if (showsStrip) VISIBLE else GONE
        recordingStrip.render(state)
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

    // Room under the draft for the recording's row, which the field grows by on Telegram's curve
    private fun setDraftRowRoom(isShown: Boolean) {
        draftRoomAnimator?.cancel()
        val target = if (isShown) DRAFT_ROW_ROOM.dp else DRAFT_BOTTOM_PADDING.dp
        if (editText.paddingBottom == target) return
        draftRoomAnimator = ValueAnimator.ofInt(editText.paddingBottom, target).apply {
            val isAnimated = isAttachedToWindow && WGlobalStorage.getAreAnimationsActive()
            duration = if (isAnimated) DRAFT_FADE_MS else 0L
            interpolator = TELEGRAM_CURVE
            addUpdateListener { animation ->
                editText.setPaddingRelative(
                    editText.paddingStart,
                    editText.paddingTop,
                    editText.paddingEnd,
                    animation.animatedValue as Int
                )
            }
            start()
        }
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

    // Hands-free, TalkBack goes to the microphone that finishes; recognizing, to the strip's status;
    // back from recognizing, to the field
    private fun moveAccessibilityFocus(previous: AgentDictationState, state: AgentDictationState) {
        if (!isAccessibilityEnabled()) return
        val hasBeenLocked = previous.phase == AgentDictationPhase.RECORDING && previous.locked
        val target = when {
            state.phase == AgentDictationPhase.RECORDING && state.locked && !hasBeenLocked ->
                microphoneButton

            state.phase == AgentDictationPhase.RECOGNIZING &&
                previous.phase != AgentDictationPhase.RECOGNIZING -> recordingStrip.statusView

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

    // Hold to record; release in place to transcribe, toward the cross to cancel, or toward Send to send
    private fun handleMicrophoneTouch(event: MotionEvent): Boolean {
        if (isTouchExplorationEnabled()) return false
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
                // A finger lifted before the recording started is a tap, which records hands-free
                val isHold = dictationState.phase != AgentDictationPhase.PRESSING
                endMicrophoneGesture()
                dictation?.release(
                    horizontalDp = (event.rawX - touchStartX) / density,
                    upDp = (touchStartY - event.rawY) / density,
                    horizontalVelocity = horizontalVelocity,
                    upVelocity = upVelocity,
                    cancelDirection = cancelDirection
                )
                isGestureEndClick = isHold
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
        supportGlass?.updateTheme()

        recordingCircle.updateTheme()
        recordingStrip.updateTheme()
        fieldGlow.updateTheme()
        fieldRim.updateTheme()

        applySendButtonTheme()
        animateInputPadding()
    }
}

internal fun sendAgentDictationText(
    draft: String,
    text: String,
    onDraftChanged: (String) -> Unit,
    onSend: ((String) -> Boolean)?
) {
    val question = listOf(draft.trim(), text.trim()).filter { it.isNotEmpty() }.joinToString(" ")
    if (question.isEmpty()) return
    onDraftChanged(question)
    if (onSend?.invoke(question) == true) onDraftChanged("")
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

/**
 * What the composer's buttons show: the microphone inside the field, the send button or Stop at the field's end, and
 * the support circle beside the field
 */
internal data class AgentComposerButtons(
    val isSendShown: Boolean,
    /** Stop stands in the send button's place */
    val isStopShown: Boolean,
    /** The microphone shows inside the field, before the send button or Stop */
    val isMicrophoneShown: Boolean,
    /** The support circle stands apart from the field; otherwise it is merged into the field's end */
    val isCircleApart: Boolean
)

internal fun agentComposerButtons(
    phase: AgentDictationPhase,
    hasText: Boolean,
    isAnswering: Boolean,
    isSupportOffered: Boolean = false,
    isSendAlwaysShown: Boolean = false
): AgentComposerButtons {
    val isIdle = phase == AgentDictationPhase.IDLE || phase == AgentDictationPhase.PRESSING ||
        phase == AgentDictationPhase.FAILED
    val button = resolveAgentComposerButton(hasText, isAnswering)
    return AgentComposerButtons(
        // A draft keeps its send button; it greys out while the Agent can't take the question. A
        // chat keeps it for an empty field too and while a recording is recognized, and a recording
        // shows it in the field
        isSendShown = phase == AgentDictationPhase.RECORDING ||
            (isSendAlwaysShown && phase == AgentDictationPhase.RECOGNIZING) ||
            (
                isIdle && (
                    button == AgentComposerButton.SEND ||
                        (isSendAlwaysShown && button == AgentComposerButton.MICROPHONE)
                    )
                ),
        isStopShown = isAnswering && !hasText &&
            (phase == AgentDictationPhase.IDLE || phase == AgentDictationPhase.FAILED),
        // The microphone stays under the recording circle, whose checkmark finishes a locked recording, and gives way
        // to the recognition's strip
        isMicrophoneShown = phase != AgentDictationPhase.RECOGNIZING,
        // The support circle stands beside the empty field and merges into it for a draft or a recording
        isCircleApart = isSupportOffered && isIdle && !hasText
    )
}
