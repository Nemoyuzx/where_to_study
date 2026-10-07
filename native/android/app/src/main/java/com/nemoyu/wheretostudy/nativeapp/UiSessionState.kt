package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ScrollView

/** Plain memory-only values: no Activity, View, callback, Parcelable or password persistence. */
internal data class InputDraft(val text: String, val selectionStart: Int, val selectionEnd: Int, val focused: Boolean)
internal data class SettingsPageDraft(
    val inputs: Map<String, InputDraft>,
    val campusIndex: Int?,
    val useAcademicPassword: Boolean,
    val automaticTerm: Boolean?,
    val customEnabled: Boolean?,
    val reminderOffsets: List<String>?,
    val qmplusDetailsExpanded: Boolean? = null,
)
internal data class ScrollAnchor(val key: String?, val offsetDp: Float, val fallbackY: Int)

internal fun uiDescendants(view: View): Sequence<View> = sequence {
    yield(view)
    if (view is ViewGroup) repeat(view.childCount) { yieldAll(uiDescendants(view.getChildAt(it))) }
}

internal fun View.sessionKey(): String? = when {
    id != View.NO_ID -> "id/$id"
    tag is String -> "tag/${tag as String}"
    else -> null
}

internal fun ScrollView.captureAnchor(): ScrollAnchor {
    val body = getChildAt(0) as? ViewGroup ?: return ScrollAnchor(null, 0f, scrollY)
    val candidates = uiDescendants(body).filter { it !== body }.mapNotNull { view ->
        val key = view.sessionKey() ?: return@mapNotNull null
        val rect = Rect(0, 0, view.width, view.height)
        body.offsetDescendantRectToMyCoords(view, rect)
        if (!view.isShown || view.height <= 0) null else Triple(key, rect.top, rect.bottom)
    }.toList()
    val anchor = candidates.filter { it.second <= scrollY && it.third > scrollY }.maxByOrNull { it.second }
        ?: candidates.filter { it.second >= scrollY }.minByOrNull { it.second }
    return ScrollAnchor(anchor?.first, ((anchor?.second ?: scrollY) - scrollY) / resources.displayMetrics.density, scrollY)
}

internal fun ScrollView.restoreAnchor(anchor: ScrollAnchor) {
    val body = getChildAt(0) as? ViewGroup ?: return
    val target = anchor.key?.let { key -> uiDescendants(body).firstOrNull { it.sessionKey() == key } }
    val y = if (target == null) anchor.fallbackY else {
        val rect = Rect(0, 0, target.width, target.height)
        body.offsetDescendantRectToMyCoords(target, rect)
        (rect.top - anchor.offsetDp * resources.displayMetrics.density).toInt()
    }
    scrollTo(0, y.coerceAtLeast(0))
}

internal fun captureInputDrafts(root: View): Map<String, InputDraft> = uiDescendants(root)
    .filterIsInstance<EditText>().filter { it.id != R.id.qmplus_saved_login_password }.mapNotNull { field -> field.sessionKey()?.let { key ->
        key to InputDraft(field.text.toString(), field.selectionStart, field.selectionEnd, field.hasFocus())
    } }.toMap()
