package com.nemoyu.wheretostudy.nativeapp

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.TargetApi
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean

/** Only this app's decor is drawn; no screen API, persistence or image history. */
internal class LanguageChangeTransition(private val forceLegacyBlur: Boolean = false) {
    private val handler = Handler(Looper.getMainLooper())
    private val revision = AtomicLong()
    private var host = WeakReference<ViewGroup>(null)
    private var content = WeakReference<View>(null)
    private var cover: FrameLayout? = null
    private var completionIcon: ImageView? = null
    private var progressLabel: TextView? = null
    private var completionDelay: Runnable? = null
    private var reducedMotion = false
    private var bitmap: Bitmap? = null
    private var animator: ValueAnimator? = null
    private var observer: ViewTreeObserver.OnPreDrawListener? = null
    private var pendingApply: (() -> Unit)? = null
    private var targetReady: (() -> Boolean)? = null
    private var deadline: Runnable? = null
    private var worker: java.util.concurrent.ExecutorService? = null
    private val workerLease = AtomicBoolean(false)
    private var leaseWait: Runnable? = null
    private val stableLayout = LanguageLayoutReadiness()
    private var nativeBlur = false
    private var closed = false
    internal var phase = "idle"
        private set
    internal var readyFrameCount = 0
        private set

    fun request(host: ViewGroup, content: View, label: String, change: () -> Unit, ready: () -> Boolean) {
        cancel()
        if (closed || !host.isAttachedToWindow) { change(); return }
        val token = revision.incrementAndGet()
        this.host = WeakReference(host); this.content = WeakReference(content)
        pendingApply = change; targetReady = ready; stableLayout.reset(); readyFrameCount = 0
        reducedMotion = reducesMotion(host)
        nativeBlur = !reducedMotion && !(forceLegacyBlur && BuildConfig.DEBUG && DailyCourseNotificationRuntimeMode.isUiTesting) && Build.VERSION.SDK_INT >= 31 && content.isHardwareAccelerated
        val layer = FrameLayout(host.context).apply {
            tag = "overlay.language-transition"; isClickable = true; isFocusable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            contentDescription = label
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            addView(TextView(context).apply {
                text = "Switching…"; progressLabel = this; textSize = 15f; gravity = Gravity.CENTER
                setTextColor(Palette.text); setPadding(24, 12, 24, 12)
                background = themedRoundedBackground(context, { Palette.surface }, radius = 8)
            }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        }
        layer.addView(ImageView(host.context).apply {
            completionIcon = this; setImageResource(R.drawable.ic_section_check)
            imageTintList = android.content.res.ColorStateList.valueOf(Palette.primaryText)
            visibility = View.GONE
        }, FrameLayout.LayoutParams(host.context.dp(30), host.context.dp(30), Gravity.CENTER))
        cover = layer
        host.addView(layer, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        phase = "covering"
        deadline = Runnable { if (revision.get() == token) { applyPending(); cancel() } }
            .also { handler.postDelayed(it, 4_000) }
        if (reducedMotion) { phase = "waiting-layout"; applyPending(); awaitLayout(token) }
        else if (nativeBlur) coverThenApply(token)
        else startLegacyBlur(token)
    }

    private fun startLegacyBlur(token: Long) {
        if (revision.get() != token || cover == null) return
        if (!workerLease.compareAndSet(false, true)) {
            val weakOwner = WeakReference(this)
            leaseWait = Runnable { weakOwner.get()?.startLegacyBlur(token) }.also { handler.postDelayed(it, 16) }
            return
        }
        leaseWait = null
        val root = host.get()
        cover?.visibility = View.INVISIBLE
        val captured = root?.let(::captureOwnedDecor)
        cover?.visibility = View.VISIBLE
        if (captured != null) {
            val weakOwner = WeakReference(this)
            val executor = worker ?: Executors.newSingleThreadExecutor().also { worker = it }
            val deliveryHandler = handler
            val lease = workerLease
            executor.execute {
                var pixels: IntArray? = null
                var transferred = false
                try {
                    val buffer = IntArray(captured.width * captured.height).also { pixels = it }
                    captured.getPixels(buffer, 0, captured.width, 0, 0, captured.width, captured.height)
                    LanguageTransitionLogic.blur(buffer, captured.width, captured.height) {
                        weakOwner.get()?.revision?.get() != token || Thread.currentThread().isInterrupted
                    }
                    captured.setPixels(buffer, 0, captured.width, 0, 0, captured.width, captured.height)
                    transferred = deliveryHandler.post {
                        lease.set(false)
                        val owner = weakOwner.get()
                        if (owner == null || owner.revision.get() != token || owner.cover == null) captured.recycle()
                        else { owner.installLegacyBlur(captured); owner.coverThenApply(token) }
                    }
                } catch (_: Throwable) {
                    deliveryHandler.post { lease.set(false); weakOwner.get()?.takeIf { it.revision.get() == token }?.let { it.applyPending(); it.cancel() } }
                } finally {
                    pixels?.fill(0)
                    if (!transferred && !captured.isRecycled) captured.recycle()
                    if (!transferred) lease.set(false)
                }
            }
        } else { workerLease.set(false); applyPending(); cancel() } // Allocation failure is not a claimed blur.
    }

    private fun installLegacyBlur(image: Bitmap) {
        bitmap = image
        cover?.addView(ImageView(cover!!.context).apply {
            scaleType = ImageView.ScaleType.FIT_XY; setImageBitmap(image)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, 0, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    private fun coverThenApply(token: Long) {
        animate(token, 0f, 1f, 120, update = { progress ->
            if (nativeBlur) setNativeBlur(progress)
            else cover?.getChildAt(0)?.alpha = progress
        }, completion = done@ {
            if (revision.get() != token) return@done
            phase = "waiting-layout"; applyPending(); awaitLayout(token)
        })
    }

    private fun awaitLayout(token: Long) {
        val root = host.get() ?: run { cancel(); return }
        observer = ViewTreeObserver.OnPreDrawListener {
            if (revision.get() != token) return@OnPreDrawListener true
            val body = content.get()
            val geometry = body?.let(::layoutGeometry)
            val bounds = listOf(root.width, root.height, body?.width ?: 0, body?.height ?: 0) + geometry.orEmpty()
            val ready = targetReady?.invoke() == true
            if (stableLayout.observe(ready, root.isAttachedToWindow, !ready,
                    root.isLayoutRequested || body?.isLayoutRequested != false || geometry == null, bounds)) {
                readyFrameCount = 3
                removeObserver(); phase = "complete"
                deadline?.let(handler::removeCallbacks); deadline = null
                progressLabel?.visibility = View.GONE; completionIcon?.visibility = View.VISIBLE
                completionDelay = Runnable {
                  if (revision.get() != token) return@Runnable
                  completionDelay = null; phase = "revealing"
                  animate(token, 1f, 0f, if (reducedMotion) 0 else 220, { progress ->
                    if (nativeBlur) setNativeBlur(progress) else cover?.alpha = progress
                  }) { if (revision.get() == token) cleanup() }
                }.also { handler.postDelayed(it, 140) }
            } else root.postInvalidateOnAnimation()
            true
        }.also(root.viewTreeObserver::addOnPreDrawListener)
        root.postInvalidateOnAnimation()
    }

    private fun applyPending() { val change = pendingApply; pendingApply = null; change?.invoke() }

    private fun layoutGeometry(root: View): List<Int>? {
        if (root.visibility != View.VISIBLE) return null
        val result = mutableListOf<Int>()
        val queue = java.util.ArrayDeque<View>(); queue.add(root)
        var count = 0
        while (queue.isNotEmpty()) {
            val view = queue.removeFirst()
            // GONE children are not measured by their parent and can retain
            // FORCE_LAYOUT. They are not part of the current visible locale.
            if (view.visibility != View.VISIBLE) continue
            if (++count > 2048 || view.isLayoutRequested) return null
            result.addAll(listOf(view.left, view.top, view.width, view.height, view.scrollX, view.scrollY,
                view.layoutDirection, view.visibility, (view.translationX * 1000).toInt(),
                (view.translationY * 1000).toInt(), (view.alpha * 1000).toInt()))
            if (view is ViewGroup) for (index in 0 until view.childCount) {
                val child = view.getChildAt(index)
                if (child.visibility == View.VISIBLE) queue.add(child)
            }
        }
        return result
    }

    fun runLocalLanguageWork(work: () -> Unit) {
        if (closed) return
        val executor = worker ?: Executors.newSingleThreadExecutor().also { worker = it }
        executor.execute(work)
    }

    fun finishImmediately() { applyPending(); cancel() }

    fun cancel() { revision.incrementAndGet(); pendingApply = null; cleanup() }

    fun close() { closed = true; cancel(); worker?.shutdownNow(); worker = null }

    private fun cleanup() {
        animator?.removeAllListeners(); animator?.cancel(); animator = null
        deadline?.let(handler::removeCallbacks); deadline = null
        completionDelay?.let(handler::removeCallbacks); completionDelay = null
        leaseWait?.let(handler::removeCallbacks); leaseWait = null
        removeObserver(); targetReady = null; stableLayout.reset()
        if (nativeBlur && Build.VERSION.SDK_INT >= 31) content.get()?.setRenderEffect(null)
        cover?.let { (it.parent as? ViewGroup)?.removeView(it); it.removeAllViews() }; cover = null
        bitmap?.takeUnless(Bitmap::isRecycled)?.recycle(); bitmap = null
        progressLabel = null; completionIcon = null
        content.clear(); host.clear(); phase = "idle"
    }

    private fun removeObserver() {
        observer?.let { listener -> host.get()?.viewTreeObserver?.takeIf { it.isAlive }?.removeOnPreDrawListener(listener) }
        observer = null
    }

    private fun animate(token: Long, start: Float, end: Float, durationMillis: Long,
        update: (Float) -> Unit, completion: () -> Unit) {
        animator?.removeAllListeners(); animator?.cancel()
        animator = ValueAnimator.ofFloat(start, end).apply {
            duration = durationMillis
            addUpdateListener { if (revision.get() == token) update(it.animatedValue as Float) }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) { if (revision.get() == token) completion() }
            })
            start()
        }
    }

    @TargetApi(31) private fun setNativeBlur(progress: Float) {
        content.get()?.setRenderEffect(if (progress <= 0f) null else
            RenderEffect.createBlurEffect(18f * progress, 18f * progress, Shader.TileMode.CLAMP))
    }

    private fun captureOwnedDecor(root: ViewGroup): Bitmap? {
        var allocated: Bitmap? = null
        return try {
            val (width, height) = LanguageTransitionLogic.bufferSize(root.width, root.height)
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { image ->
                allocated = image
                check(image.allocationByteCount <= LanguageTransitionLogic.MAXIMUM_BITMAP_BYTES)
                val canvas = Canvas(image)
                canvas.scale(width.toFloat() / root.width, height.toFloat() / root.height)
                root.draw(canvas)
            }
        } catch (_: Throwable) { allocated?.takeUnless(Bitmap::isRecycled)?.recycle(); null }
    }

    private fun reducesMotion(view: View): Boolean = if (Build.VERSION.SDK_INT >= 26)
        !ValueAnimator.areAnimatorsEnabled() else Settings.Global.getFloat(view.context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
}
