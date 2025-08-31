package me.everything.android.ui.overscroll;

import static java.lang.Double.min;
import static me.everything.android.ui.overscroll.IOverScrollState.STATE_BOUNCE_BACK;
import static me.everything.android.ui.overscroll.IOverScrollState.STATE_BOUNCE_FORWARD;
import static me.everything.android.ui.overscroll.IOverScrollState.STATE_DRAG_END_SIDE;
import static me.everything.android.ui.overscroll.IOverScrollState.STATE_DRAG_START_SIDE;
import static me.everything.android.ui.overscroll.IOverScrollState.STATE_IDLE;
import static me.everything.android.ui.overscroll.ListenerStubs.OverScrollStateListenerStub;
import static me.everything.android.ui.overscroll.ListenerStubs.OverScrollUpdateListenerStub;

import android.animation.Animator;
import android.animation.ValueAnimator;
import android.util.Log;
import android.util.Property;
import android.view.MotionEvent;
import android.view.View;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.Interpolator;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.Date;

import me.everything.android.ui.overscroll.adapters.IOverScrollDecoratorAdapter;
import me.everything.android.ui.overscroll.adapters.RecyclerViewOverScrollDecorAdapter;

/**
 * A standalone view decorator adding over-scroll with a smooth bounce-back effect to (potentially) any view -
 * provided that an appropriate {@link IOverScrollDecoratorAdapter} implementation exists / can be written
 * for that view type (e.g. {@link RecyclerViewOverScrollDecorAdapter}).
 *
 * <p>Design-wise, being a standalone class, this decorator powerfully provides the ability to add
 * the over-scroll effect over any view without adjusting the view's implementation. In essence, this
 * eliminates the need to repeatedly implement the effect per each view type (list-view,
 * recycler-view, image-view, etc.). Therefore, using it is highly recommended compared to other
 * more intrusive solutions.</p>
 *
 * <p>Note that this class is abstract, having {@link HorizontalOverScrollBounceEffectDecorator} and
 * {@link VerticalOverScrollBounceEffectDecorator} providing concrete implementations that are
 * view-orientation specific.</p>
 *
 * <hr width="97%"/>
 * <h2>Implementation Notes</h2>
 *
 * <p>At it's core, the class simply registers itself as a touch-listener over the decorated view and
 * intercepts touch events as needed.</p>
 *
 * <p>Internally, it delegates the over-scrolling calculations onto 3 state-based classes:
 * <ol>
 *     <li><b>Idle state</b> - monitors view state and touch events to intercept over-scrolling initiation
 *     (in which case it hands control over to the Over-scrolling state).</li>
 *     <li><b>Over-scrolling state</b> - handles motion events to apply the over-scroll effect as users
 *     interact with the view.</li>
 *     <li><b>Bounce-back state</b> - runs the bounce-back animation, all-the-while blocking all
 *     touch events till the animation completes (in which case it hands control back to the idle
 *     state).</li>
 * </ol>
 * </p>
 *
 * @see RecyclerViewOverScrollDecorAdapter
 * @see IOverScrollDecoratorAdapter
 */
public abstract class OverScrollBounceEffectDecoratorBase implements IOverScrollDecor, View.OnTouchListener {

    public static final String TAG = "OverScrollDecor";

    public static final float DEFAULT_DECELERATE_FACTOR = -2f;

    public static final boolean BOUNCE_FORWARD_ENABLED = false;

    protected final OverScrollStartAttributes mStartAttr = new OverScrollStartAttributes();
    protected final IOverScrollDecoratorAdapter mViewAdapter;

    protected final IdleState mIdleState;
    protected final OverScrollingState mOverScrollingState;
    protected final BounceBackState mBounceBackState;
    protected final BounceForwardState mBounceForwardState;
    protected IDecoratorState mCurrentState;
    protected IOverScrollStateListener mStateListener = new OverScrollStateListenerStub();
    protected IOverScrollUpdateListener mUpdateListener = new OverScrollUpdateListenerStub();
    /**
     * When in over-scroll mode, keep track of dragging velocity to provide a smooth slow-down
     * for the bounce-back effect.
     */
    protected float mVelocity;
    protected FlingData mFlingData;
    protected float maxOffset = Float.MAX_VALUE;

    public OverScrollBounceEffectDecoratorBase(IOverScrollDecoratorAdapter viewAdapter, float decelerateFactor) {
        mViewAdapter = viewAdapter;

        mBounceBackState = new BounceBackState(decelerateFactor);
        mOverScrollingState = new OverScrollingState();
        mIdleState = new IdleState();
        mBounceForwardState = new BounceForwardState(decelerateFactor);

        mCurrentState = mIdleState;

        attach();
    }

    @Override
    public boolean onTouch(View v, MotionEvent event) {
        switch (event.getAction()) {
            case MotionEvent.ACTION_DOWN:
                mOverScrollingState.mMoveAttr.mAbsAdditionalOffset = 0;
                mFlingData = null;

            case MotionEvent.ACTION_MOVE:
                return mCurrentState.handleMoveTouchEvent(event);

            case MotionEvent.ACTION_CANCEL:
            case MotionEvent.ACTION_UP:
                return mCurrentState.handleUpOrCancelTouchEvent(event);
        }

        return false;
    }

    @Override
    public void setOverScrollStateListener(IOverScrollStateListener listener) {
        mStateListener = (listener != null ? listener : new OverScrollStateListenerStub());
    }

    @Override
    public void setOverScrollUpdateListener(IOverScrollUpdateListener listener) {
        mUpdateListener = (listener != null ? listener : new OverScrollUpdateListenerStub());
    }

    @Override
    public int getCurrentState() {
        return mCurrentState.getStateId();
    }

    @Override
    public View getView() {
        return mViewAdapter.getView();
    }

    protected void issueStateTransition(IDecoratorState state) {
        IDecoratorState oldState = mCurrentState;
        mCurrentState = state;
        mCurrentState.handleEntryTransition(oldState);
    }

    protected void attach() {
        getView().setOnTouchListener(this);
        getView().setOverScrollMode(View.OVER_SCROLL_NEVER);
        setupRecyclerViewForwardBounce();
    }

    private void setupRecyclerViewForwardBounce() {
        RecyclerView recyclerView = (RecyclerView) mViewAdapter.getView();
        if (recyclerView != null) {
            RecyclerView.OnFlingListener existingFlingListener = recyclerView.getOnFlingListener();
            recyclerView.setOnFlingListener(new RecyclerView.OnFlingListener() {
                @Override
                public boolean onFling(int velocityX, int velocityY) {
                    if (existingFlingListener != null) {
                        boolean existingFlingResult = existingFlingListener.onFling(velocityX, velocityY);
                        if (existingFlingResult)
                            return true;
                    }
                    if (!BOUNCE_FORWARD_ENABLED)
                        return false;
                    float currentOffset = recyclerView.computeVerticalScrollOffset();
                    if (currentOffset <= 0) // prevent glitches on some devices
                        return false;
                    int flingTime = (int) OverScrollCalculationHelper.Companion.computeOverScrollTime(Math.abs(velocityY));
                    float flingDistance = OverScrollCalculationHelper.Companion.computeOverScrollDistance(Math.abs(velocityY));
                    mFlingData = new FlingData(currentOffset, velocityY, flingDistance, flingTime);
                    return false;
                }
            });
            recyclerView.addOnScrollListener(new RecyclerView.OnScrollListener() {
                @Override
                public void onScrollStateChanged(@NonNull RecyclerView recyclerView, int newState) {
                    super.onScrollStateChanged(recyclerView, newState);

                    if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                        onFlingFinished();
                    }
                }

                private void onFlingFinished() {
                    if (mFlingData == null)
                        return;
                    if (mCurrentState == mBounceBackState) { // prevent glitches on some devices
                        mFlingData = null;
                        return;
                    }
                    if (mFlingData.startVelocity < 0 && !recyclerView.canScrollVertically(-1)) {
                        if (mFlingData.scrollDistance > mFlingData.startOffset) {
                            mVelocity = OverScrollCalculationHelper.Companion.computeOverscrollVelocityAtDistance(mFlingData.startVelocity, mFlingData.startOffset) / 1000;
                            mBounceForwardState.setTarget(mFlingData.scrollDistance - mFlingData.startOffset, mFlingData.totalTime - (new Date().getTime() - mFlingData.timestamp));
                            issueStateTransition(mBounceForwardState);
                        }
                    } else if (mFlingData.startVelocity > 0 && !recyclerView.canScrollVertically(1)) {
                        float newOffset = recyclerView.computeVerticalScrollOffset();
                        float scrolledY = newOffset - mFlingData.startOffset;
                        if (mFlingData.scrollDistance > scrolledY) {
                            mVelocity = OverScrollCalculationHelper.Companion.computeOverscrollVelocityAtDistance(mFlingData.startVelocity, scrolledY) / 1000;
                            mBounceForwardState.setTarget(scrolledY - mFlingData.scrollDistance, mFlingData.totalTime - (new Date().getTime() - mFlingData.timestamp));
                            issueStateTransition(mBounceForwardState);
                        }
                    }
                    mFlingData = null;
                }
            });
        }
    }

    @Override
    public void detach() {
        if (mCurrentState != mIdleState) {
            Log.w(TAG, "Decorator detached while over-scroll is in effect. You might want to add a precondition of that getCurrentState()==STATE_IDLE, first.");
        }
        getView().setOnTouchListener(null);
        getView().setOverScrollMode(View.OVER_SCROLL_ALWAYS);
    }

    public void setBounceBackSkipValue(int y) {
        mBounceBackState.setSkipY(y);
    }

    public void setMaxOffset(float maxOffset) {
        this.maxOffset = maxOffset;
    }

    public void scrollTo(int value) {
        mBounceForwardState.setRealTarget(value, 250);
        issueStateTransition(mBounceForwardState);
    }

    public void comeBackFromOverScrollValue(int value) {
        if (getCurrentState() == STATE_BOUNCE_FORWARD)
            return;
        mBounceBackState.setStartX(value);
        issueStateTransition(mBounceBackState);
    }

    public float getOverScrollOffset() {
        return mOverScrollingState.mMoveAttr.mAbsOffset;
    }

    protected abstract MotionAttributes createMotionAttributes();

    protected abstract AnimationAttributes createAnimationAttributes();

    protected abstract void translateView(View view, float offset);

    protected abstract void translateViewAndEvent(View view, float offset, MotionEvent event);

    /**
     * Interface of decorator-state delegation classes. Defines states as handles of two fundamental
     * touch events: actual movement, up/cancel.
     */
    protected interface IDecoratorState {

        /**
         * Handle a motion (touch) event.
         *
         * @param event The event from onTouch.
         * @return Return value for onTouch.
         */
        boolean handleMoveTouchEvent(MotionEvent event);

        /**
         * Handle up / touch-cancel events.
         *
         * @param event The event from onTouch.
         * @return Return value for onTouch.
         */
        boolean handleUpOrCancelTouchEvent(MotionEvent event);

        /**
         * Handle a transition onto this state, as it becomes 'current' state.
         *
         * @param fromState Previous state
         */
        void handleEntryTransition(IDecoratorState fromState);

        /**
         * The client-perspective ID of the state associated with this (internal) one. ID's
         * are as specified in {@link IOverScrollState}.
         *
         * @return The ID, e.g. {@link IOverScrollState#STATE_IDLE}.
         */
        int getStateId();
    }

    /**
     * Motion attributes: keeps data describing current motion event.
     * <br/>Orientation agnostic: subclasses provide either horizontal or vertical
     * initialization of the agnostic attributes.
     */
    protected abstract static class MotionAttributes {
        public float mAbsOffset;
        public float mAbsAdditionalOffset;
        public float mDeltaOffset;
        public boolean mDir; // True = 'forward', false = 'backwards'.

        protected abstract boolean init(View view, MotionEvent event);
    }

    protected static class OverScrollStartAttributes {
        protected int mPointerId;
        protected float mAbsOffset;
        protected boolean mDir; // True = 'forward', false = 'backwards'.
    }

    protected abstract static class AnimationAttributes {
        public Property<View, Float> mProperty;
        public float mAbsOffset;
        public float mMaxOffset;

        protected abstract void init(View view);
    }

    public static class FlingData {
        float startOffset;
        float startVelocity;
        float scrollDistance;
        int totalTime;
        long timestamp;

        public FlingData(float startOffset, float startVelocity, float scrollDistance, int totalTime) {
            this.startOffset = startOffset;
            this.startVelocity = startVelocity;
            this.scrollDistance = scrollDistance;
            this.totalTime = totalTime;
            this.timestamp = new Date().getTime();
        }
    }

    /**
     * Idle state: monitors move events, trying to figure out whether over-scrolling should be
     * initiated (i.e. when scrolled further when the view is at one of its displayable ends).
     * <br/>When such is the case, it hands over control to the over-scrolling state.
     */
    protected class IdleState implements IDecoratorState {

        final MotionAttributes mMoveAttr;

        public IdleState() {
            mMoveAttr = createMotionAttributes();
        }

        @Override
        public int getStateId() {
            return STATE_IDLE;
        }

        @Override
        public boolean handleMoveTouchEvent(MotionEvent event) {
            final View view = mViewAdapter.getView();
            if (!mMoveAttr.init(view, event)) {
                return false;
            }

            // Has over-scrolling officially started?
            if ((mViewAdapter.isInAbsoluteStart() && mMoveAttr.mDir) ||
                (mViewAdapter.isInAbsoluteEnd() && !mMoveAttr.mDir)) {

                // Save initial over-scroll attributes for future reference.
                mStartAttr.mPointerId = event.getPointerId(0);
                mStartAttr.mAbsOffset = mMoveAttr.mAbsOffset;
                mStartAttr.mDir = mMoveAttr.mDir;

                issueStateTransition(mOverScrollingState);
                return mOverScrollingState.handleMoveTouchEvent(event);
            }

            return false;
        }

        @Override
        public boolean handleUpOrCancelTouchEvent(MotionEvent event) {
            return false;
        }

        @Override
        public void handleEntryTransition(IDecoratorState fromState) {
            mStateListener.onOverScrollStateChange(OverScrollBounceEffectDecoratorBase.this, fromState.getStateId(), this.getStateId());
        }
    }

    /**
     * Handles the actual over-scrolling: thus translating the view according to configuration
     * and user interactions, dynamically.
     * <p>
     * <br/><br/>The state is exited - thus completing over-scroll handling, in one of two cases:
     * <br/>When user lets go of the view, it transitions control to the bounce-back state.
     * <br/>When user moves the view back onto a potential 'under-scroll' state, it abruptly
     * transitions control to the idle-state, so as to return touch-events management to the
     * normal over-scroll-less environment (thus preventing under-scrolling and potentially regaining
     * regular scrolling).
     */
    protected class OverScrollingState implements IDecoratorState {

        final MotionAttributes mMoveAttr;
        protected MotionEvent cachedEvent;
        int mCurrDragState;

        public OverScrollingState() {
            mMoveAttr = createMotionAttributes();
        }

        @Override
        public int getStateId() {
            // This is really a single class that implements 2 states, so our ID depends on what
            // it was during the last invocation.
            return mCurrDragState;
        }

        @Override
        public boolean handleMoveTouchEvent(MotionEvent event) {
            cachedEvent = event;

            // Switching 'pointers' (e.g. fingers) on-the-fly isn't supported -- abort over-scroll
            // smoothly using the default bounce-back animation in this case.
            if (mStartAttr.mPointerId != event.getPointerId(0)) {
                issueStateTransition(mBounceBackState);
                return true;
            }

            final View view = mViewAdapter.getView();
            if (!mMoveAttr.init(view, event)) {
                // Keep intercepting the touch event as long as we're still over-scrolling...
                return true;
            }

            double prevX = OverScrollCalculationHelper.Companion.findXFromY(Math.abs(mMoveAttr.mAbsOffset));
            double newX = prevX + mMoveAttr.mDeltaOffset * (mMoveAttr.mAbsOffset < 0 ? -1 : 1);
            float newY = (float) ((newX < 0) ? newX : (OverScrollCalculationHelper.Companion.calculateY(newX))) * (mMoveAttr.mAbsOffset < 0 ? -1 : 1);
            double deltaOffset = newY - mMoveAttr.mAbsOffset;
            float newOffset = Math.min(newY + mMoveAttr.mAbsAdditionalOffset, maxOffset);
            mMoveAttr.mAbsAdditionalOffset = 0;

            // If moved in counter direction onto a potential under-scroll state -- don't. Instead, abort
            // over-scrolling abruptly, thus returning control to which-ever touch handlers there
            // are waiting (e.g. regular scroller handlers).
            if ((mStartAttr.mDir && !mMoveAttr.mDir && (newOffset <= mStartAttr.mAbsOffset)) ||
                (!mStartAttr.mDir && mMoveAttr.mDir && (newOffset >= mStartAttr.mAbsOffset))) {
                translateViewAndEvent(view, mStartAttr.mAbsOffset, event);
                mUpdateListener.onOverScrollUpdate(OverScrollBounceEffectDecoratorBase.this, true, mCurrDragState, 0, mVelocity);

                issueStateTransition(mIdleState);
                return true;
            }

            if (view.getParent() != null) {
                view.getParent().requestDisallowInterceptTouchEvent(true);
            }

            long dt = event.getEventTime() - event.getHistoricalEventTime(0);
            if (dt > 0) { // Sometimes (though rarely) dt==0 cause originally timing is in nanos, but is presented in millis.
                mVelocity = (float) (deltaOffset / dt);
            }

            translateView(view, newOffset);
            mUpdateListener.onOverScrollUpdate(OverScrollBounceEffectDecoratorBase.this, true, mCurrDragState, newOffset, mVelocity);

            return true;
        }

        @Override
        public boolean handleUpOrCancelTouchEvent(MotionEvent event) {
            issueStateTransition(mBounceBackState);
            return false;
        }

        @Override
        public void handleEntryTransition(IDecoratorState fromState) {
            mCurrDragState = (mStartAttr.mDir ? STATE_DRAG_START_SIDE : STATE_DRAG_END_SIDE);
            mStateListener.onOverScrollStateChange(OverScrollBounceEffectDecoratorBase.this, fromState.getStateId(), this.getStateId());
        }
    }

    /**
     * When entered, starts the bounce-back animation.
     * <br/>Upon animation completion, transitions control onto the idle state; Does so by
     * registering itself as an animation listener.
     * <br/>In the meantime, blocks (intercepts) all touch events.
     */
    protected class BounceBackState implements IDecoratorState {

        protected final Interpolator mBounceBackInterpolator = new DecelerateInterpolator();
        protected final float mDecelerateFactor;
        protected final float mDoubleDecelerateFactor;

        protected final AnimationAttributes mAnimAttributes;

        private int startX = 0;
        private float skipY = 0;

        public BounceBackState(float decelerateFactor) {
            mDecelerateFactor = decelerateFactor;
            mDoubleDecelerateFactor = 2f * decelerateFactor;

            mAnimAttributes = createAnimationAttributes();
        }

        @Override
        public int getStateId() {
            return STATE_BOUNCE_FORWARD;
        }

        @Override
        public void handleEntryTransition(IDecoratorState fromState) {
            mStateListener.onOverScrollStateChange(OverScrollBounceEffectDecoratorBase.this, fromState.getStateId(), this.getStateId());
            Animator bounceForwardAnim = createAnimator();
            bounceForwardAnim.start();
        }

        @Override
        public boolean handleMoveTouchEvent(MotionEvent event) {
            // Flush all touches down the drain till animation is over.
            return true;
        }

        @Override
        public boolean handleUpOrCancelTouchEvent(MotionEvent event) {
            // Flush all touches down the drain till animation is over.
            return true;
        }

        protected Animator createAnimator() {
            final View view = mViewAdapter.getView();
            mAnimAttributes.init(view);
            return createBounceBackAnimator();
        }

        protected Animator createBounceBackAnimator() {
            final View view = mViewAdapter.getView();

            int realStartX = startX != 0 ? startX : (int) mAnimAttributes.mAbsOffset;
            float animationDistance = skipY > 0 ? Math.max(0, realStartX - skipY) : realStartX;
            float startValue = (animationDistance > 0 ? 1 : -1) * Math.max(0, Math.abs(animationDistance));
            float endValue = 0;
            float velocity = mVelocity;
            ValueAnimator bounceBackAnim = ValueAnimator.ofFloat(0, 1f);
            long duration = startValue == 0 ? 0 : Long.max(100, Long.min(400, (long) (Math.abs(startValue) / 10)));
            bounceBackAnim.setDuration(duration);
            boolean callbacksEnabled = duration > 0;
            bounceBackAnim.setInterpolator(mBounceBackInterpolator);
            bounceBackAnim.addUpdateListener(animation -> {
                float progress = (float) animation.getAnimatedValue();
                float velocityFactor = (1 - progress) * velocity;
                float newVal = startValue + ((endValue - startValue) * progress) - velocityFactor;
                if (Math.abs(newVal) < Math.abs(endValue))
                    newVal = endValue;
                view.setTranslationY(newVal);
                if (callbacksEnabled)
                    mUpdateListener.onOverScrollUpdate(OverScrollBounceEffectDecoratorBase.this, false, STATE_BOUNCE_BACK, newVal, mVelocity);
            });
            bounceBackAnim.addListener(new Animator.AnimatorListener() {
                @Override
                public void onAnimationStart(@NonNull Animator animation) {
                    if (!callbacksEnabled)
                        mUpdateListener.onOverScrollUpdate(OverScrollBounceEffectDecoratorBase.this, false, STATE_BOUNCE_BACK, 0, mVelocity);
                }

                @Override
                public void onAnimationEnd(@NonNull Animator animation) {
                    issueStateTransition(mIdleState);
                    mUpdateListener.onOverScrollUpdate(OverScrollBounceEffectDecoratorBase.this, false, STATE_IDLE, 0, 0);
                }

                @Override
                public void onAnimationCancel(@NonNull Animator animation) {

                }

                @Override
                public void onAnimationRepeat(@NonNull Animator animation) {

                }
            });
            startX = 0;
            skipY = 0;
            mVelocity = 0;
            return bounceBackAnim;
        }

        void setStartX(int value) {
            startX = value;
        }

        void setSkipY(float offset) {
            skipY = Math.max(0, offset);
        }
    }

    protected class BounceForwardState implements IDecoratorState {

        protected final Interpolator mBounceBackInterpolator = new DecelerateInterpolator();
        protected final float mDecelerateFactor;
        protected final float mDoubleDecelerateFactor;

        protected final AnimationAttributes mAnimAttributes;

        private float targetY = 0;
        private long duration = 0;

        private boolean isTouchActive = false;

        public BounceForwardState(float decelerateFactor) {
            mDecelerateFactor = decelerateFactor;
            mDoubleDecelerateFactor = 2f * decelerateFactor;

            mAnimAttributes = createAnimationAttributes();
        }

        @Override
        public int getStateId() {
            return STATE_BOUNCE_FORWARD;
        }

        @Override
        public void handleEntryTransition(IDecoratorState fromState) {
            mStateListener.onOverScrollStateChange(OverScrollBounceEffectDecoratorBase.this, fromState.getStateId(), this.getStateId());
            Animator bounceForwardAnim = createAnimator();
            bounceForwardAnim.start();
        }

        @Override
        public boolean handleMoveTouchEvent(MotionEvent event) {
            // Flush all touches down the drain till animation is over.
            return true;
        }

        @Override
        public boolean handleUpOrCancelTouchEvent(MotionEvent event) {
            // Flush all touches down the drain till animation is over.
            return true;
        }

        protected Animator createAnimator() {
            final View view = mViewAdapter.getView();
            mAnimAttributes.init(view);
            return createBounceForwardAnimator();
        }

        protected Animator createBounceForwardAnimator() {
            final View view = mViewAdapter.getView();

            float endValue = targetY;
            float velocity = mVelocity;
            ValueAnimator bounceForwardAnim = ValueAnimator.ofFloat(0, 1f);
            bounceForwardAnim.setDuration(duration);
            bounceForwardAnim.setInterpolator(mBounceBackInterpolator);
            bounceForwardAnim.addUpdateListener(animation -> {
                float progress = (float) animation.getAnimatedValue();
                float velocityFactor = (1 - progress) * velocity;
                float newVal = (endValue * progress) - velocityFactor;
                if (Math.abs(newVal) > Math.abs(endValue))
                    newVal = endValue;
                view.setTranslationY(newVal);
                mUpdateListener.onOverScrollUpdate(OverScrollBounceEffectDecoratorBase.this, isTouchActive, STATE_BOUNCE_FORWARD, newVal, mVelocity);
            });
            bounceForwardAnim.addListener(new Animator.AnimatorListener() {
                @Override
                public void onAnimationStart(@NonNull Animator animation) {

                }

                @Override
                public void onAnimationEnd(@NonNull Animator animation) {
                    issueStateTransition(mBounceBackState);
                }

                @Override
                public void onAnimationCancel(@NonNull Animator animation) {

                }

                @Override
                public void onAnimationRepeat(@NonNull Animator animation) {

                }
            });
            targetY = 0;
            mVelocity = 0;
            return bounceForwardAnim;
        }

        void setTarget(float offset, long duration) {
            targetY =
                (float) OverScrollCalculationHelper.Companion.calculateBounceY(min(Math.abs(offset), 3000)) *
                    (offset > 0 ? 1 : -1);
            this.duration = Long.max(100, Long.min(400, duration / 10));
            isTouchActive = false;
        }

        void setRealTarget(float offset, long duration) {
            targetY = offset;
            this.duration = duration;
            isTouchActive = true;
        }
    }
}
