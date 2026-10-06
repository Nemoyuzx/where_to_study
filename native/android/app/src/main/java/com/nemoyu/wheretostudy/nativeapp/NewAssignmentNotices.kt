package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.util.AtomicFile
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

internal data class NewAssignmentNotice(val id: String, val title: String, val course: String?, val deadline: String?) {
    companion object {
        fun qmplus(snapshot: QmplusSnapshot): List<NewAssignmentNotice> {
            val visible = QmplusSnapshotCodec.ebuOnly(snapshot)
            val courses = visible.courses.filter { it.currentTermStatus != "other" }.associateBy { it.id }
            return visible.activities.filter { it.courseID in courses && it.kind in setOf("assignment", "quiz") }
                .map { NewAssignmentNotice("${it.courseID}:${it.kind}:${it.id}", it.title, courses[it.courseID]?.name,
                    it.dueAt ?: it.closesAt ?: it.cutoffAt) }
        }
        fun preview(items: List<NewAssignmentNotice>): List<NewAssignmentNotice> = items.take(8)
    }
}

internal data class NewAssignmentNoticeBatch(val id: Long, val source: String, val identity: String,
    val items: List<NewAssignmentNotice>) {
    val destination: InformationQueryMode
        get() = if (source == "qmplus") InformationQueryMode.COURSES else InformationQueryMode.ASSIGNMENTS
}

/** Kept in ActivitySessionState: claiming a dialog never removes its batch.
 * Rotation can reclaim it; only its matching dismissal acknowledges it. */
internal class NewAssignmentNoticeQueue {
    private val batches = mutableListOf<NewAssignmentNoticeBatch>()
    private var nextID = 0L
    fun add(source: String, identity: String, items: List<NewAssignmentNotice>) {
        if (items.isNotEmpty()) batches.add(NewAssignmentNoticeBatch(++nextID, source, identity, items.toList()))
    }
    fun current(): NewAssignmentNoticeBatch? = batches.firstOrNull()
    fun acknowledge(id: Long) { batches.removeAll { it.id == id } }
    fun clear(source: String) { batches.removeAll { it.source == source } }
    fun retainIdentity(source: String, identity: String) { batches.removeAll { it.source == source && it.identity != identity } }
}

internal object NewAssignmentDetection {
    fun additions(seen: Set<String>?, items: List<NewAssignmentNotice>, restored: Boolean, limit: Int): List<NewAssignmentNotice> =
        if (seen == null || restored || seen.size >= limit) emptyList()
        else items.distinctBy { it.id }.filter { it.id !in seen }
}

/** IDs only: never persist titles, accounts or authentication material. Saturated
 * scopes stop detecting rather than evicting IDs and re-alerting old coursework. */
internal class NewAssignmentNotices(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "new-assignment-seen.json"))
    private val records = runCatching { JSONObject(String(file.readFully(), Charsets.UTF_8)) }.getOrElse { JSONObject() }
    private val pending = NewAssignmentNoticeQueue()
    var onPending: (() -> Unit)? = null

    @Synchronized fun accept(source: String, identity: String, items: List<NewAssignmentNotice>, restored: Boolean) {
        val scope = "$identity:${SemesterLogic.suggestTermForDate().termId}"
        val sourceRecords = records.optJSONObject(source) ?: JSONObject().also { records.put(source, it) }
        val old = sourceRecords.optJSONArray(scope)
        val seen = linkedSetOf<String>()
        if (old != null) for (index in 0 until minOf(old.length(), MAX_IDS)) old.optString(index).takeIf { it.isNotEmpty() }?.let(seen::add)
        val additions = NewAssignmentDetection.additions(seen.takeIf { old != null }, items, restored, MAX_IDS)
        items.forEach { if (seen.size < MAX_IDS) seen.add(it.id) }
        // Only the current identity's term partitions survive account changes.
        sourceRecords.keys().asSequence().toList().filter { !it.startsWith("$identity:") }.forEach { sourceRecords.remove(it) }
        if (sourceRecords.length() >= MAX_TERMS && old == null) return
        sourceRecords.put(scope, JSONArray(seen.toList()))
        val output = runCatching { file.startWrite() }.getOrNull() ?: return
        val saved = runCatching { output.write(records.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(output) }.isSuccess
        if (!saved) { file.failWrite(output); return }
        pending.retainIdentity(source, identity)
        pending.add(source, identity, additions)
        onPending?.invoke()
    }

    @Synchronized fun clear(source: String) {
        records.remove(source)
        pending.clear(source)
        runCatching { val output = file.startWrite(); output.write(records.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(output) }
        onPending?.invoke()
    }

    @Synchronized fun current(): NewAssignmentNoticeBatch? = pending.current()
    @Synchronized fun acknowledge(id: Long) { pending.acknowledge(id) }
    private companion object { const val MAX_IDS = 10000; const val MAX_TERMS = 16 }
}
