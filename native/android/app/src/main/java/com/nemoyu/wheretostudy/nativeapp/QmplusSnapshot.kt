package com.nemoyu.wheretostudy.nativeapp

import java.net.URI
import java.nio.charset.StandardCharsets
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

/** No credentials, cookies, session tokens, timetable or application commands. */
internal data class QmplusCourse(
    val id: String, val name: String, val shortName: String?, val url: String,
    val startAt: String?, val endAt: String?, val currentTermStatus: String,
)
internal data class QmplusActivityItem(
    val id: String, val courseID: String, val title: String, val kind: String, val url: String,
    val dueAt: String?, val opensAt: String?, val closesAt: String?, val cutoffAt: String?,
    val timeLimitSeconds: Long?, val status: String?, val detailStatus: String?, val rawTimeText: String?,
)
internal data class QmplusSnapshot(
    val fetchedAt: String, val courses: List<QmplusCourse>, val activities: List<QmplusActivityItem>,
    val warnings: List<String>, val partial: Boolean = false,
)

/** An administrative mark-review request is not assessed coursework. Match
 * only the known Assignment title; preserve the original title and all dates. */
internal object QmplusCourseworkPolicy {
    private val separators = setOf(0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F,
        0x205F, 0x3000, 0xFEFF, 0x5F, 0x2D, 0x2F, 0x3A, 0x2212)

    fun isMarkReviewRequest(kind: String, title: String): Boolean {
        if (kind != "assignment") return false
        val normalized = buildString {
            var spacePending = false
            title.forEach { character ->
                var code = character.code
                if (code in 0xFF01..0xFF5E) code -= 0xFEE0
                if (code == 0x3000) code = 0x20
                if (code in 9..13 || code in 0x2000..0x200A || code in 0x2010..0x2015 || code in separators) {
                    if (isNotEmpty()) spacePending = true
                } else {
                    if (spacePending) append(' ')
                    spacePending = false
                    if (code in 0x61..0x7A) code -= 0x20
                    append(code.toChar())
                }
            }
        }
        return normalized == "COURSEWORK MARK REVIEW REQUEST" || normalized == "COURSEWORK MARK REVIEW REQUEST FORM"
    }

    fun activities(items: List<QmplusActivityItem>): List<QmplusActivityItem> =
        items.filterNot { isMarkReviewRequest(it.kind, it.title) }
}

internal object QmplusPolicy {
    const val START_URL = "https://qmplus.qmul.ac.uk/my/"
    const val MAXIMUM_SNAPSHOT_BYTES = 512 * 1024
    private val businessPaths = setOf("/my/", "/my/index.php", "/course/view.php",
        "/mod/assign/view.php", "/mod/quiz/view.php")

    fun allowsHTTPSNavigation(value: String): Boolean = trustedURI(value) != null
    fun isBusinessPage(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("qmplus.qmul.ac.uk", ignoreCase = true) && it.rawPath in businessPaths
    } == true
    fun isCourseURL(value: String): Boolean = isCanonicalBusinessURL(value) && URI(value).rawPath == "/course/view.php"
    fun isActivityURL(value: String, kind: String): Boolean = isCanonicalBusinessURL(value) &&
        URI(value).rawPath == if (kind == "assignment") "/mod/assign/view.php" else "/mod/quiz/view.php"

    private fun isCanonicalBusinessURL(value: String): Boolean = isBusinessPage(value) && URI(value).let {
        it.rawFragment == null && Regex("^id=[1-9]\\d{0,15}$").matches(it.rawQuery.orEmpty())
    }

    private fun trustedURI(value: String): URI? = runCatching { URI(value) }.getOrNull()?.takeIf {
        it.scheme.equals("https", ignoreCase = true) && !it.host.isNullOrBlank() &&
            it.rawUserInfo == null && it.port in listOf(-1, 443)
    }
}

internal object QmplusSnapshotCodec {
    /** Scope older local snapshots for presentation without changing BUPT/UCloud data. */
    fun ebuOnly(snapshot: QmplusSnapshot): QmplusSnapshot {
        val courses = snapshot.courses.filter { it.name.trimStart().startsWith("EBU", ignoreCase = true) }
        val ids = courses.map { it.id }.toSet()
        return snapshot.copy(courses = courses,
            activities = QmplusCourseworkPolicy.activities(snapshot.activities).filter { it.courseID in ids })
    }

    fun decode(bytes: ByteArray): QmplusSnapshot {
        require(bytes.size <= QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES) { "QMplus snapshot is too large." }
        val text = String(bytes, StandardCharsets.UTF_8)
        require(text.toByteArray(StandardCharsets.UTF_8).contentEquals(bytes)) { "Invalid UTF-8." }
        validateNesting(text)
        val root = JSONObject(text)
        require(root.optInt("schema_version") == 1 && root.optString("source") == "qmplus")
        require(root.getBoolean("ok")) { "QMplus synchronization did not succeed." }
        val partial = root.getBoolean("partial")
        val fetchedAt = date(root, "fetched_at") ?: error("Missing fetched_at.")
        val rawCourses = root.getJSONArray("courses")
        val rawActivities = root.getJSONArray("activities")
        val rawWarnings = root.getJSONArray("warnings")
        require(rawCourses.length() <= 100 && rawActivities.length() <= 500 && rawWarnings.length() <= 40)
        val courses = (0 until rawCourses.length()).map { index -> rawCourses.getJSONObject(index).let { course ->
            val id = required(course, "id", 128)
            QmplusCourse(id, required(course, "name", 512),
                optional(course, "short_name", 512), required(course, "url", 2048).also {
                    require(QmplusPolicy.isCourseURL(it) && URI(it).rawQuery == "id=$id")
                }, date(course, "start_at"), date(course, "end_at"),
                required(course, "current_term_status", 16).also { require(it in setOf("current", "other", "unknown")) })
        } }
        require(courses.map { it.id }.distinct().size == courses.size)
        val courseIDs = courses.map { it.id }.toSet()
        val activities = (0 until rawActivities.length()).map { index -> rawActivities.getJSONObject(index).let { item ->
            val id = required(item, "id", 128)
            val kind = required(item, "kind", 16).also { require(it in setOf("assignment", "quiz")) }
            val timeLimit = if (item.isNull("time_limit_seconds")) null else item.getLong("time_limit_seconds").also {
                require(it in 0..31_536_000)
            }
            QmplusActivityItem(id, required(item, "course_id", 128).also {
                require(it in courseIDs)
            }, required(item, "title", 512), kind, required(item, "url", 2048).also {
                require(QmplusPolicy.isActivityURL(it, kind) && URI(it).rawQuery == "id=$id")
            }, date(item, "due_at"), date(item, "opens_at"), date(item, "closes_at"), date(item, "cutoff_at"),
                timeLimit, optional(item, "status", 1000), optional(item, "detail_status", 16).also {
                    require(it == null || it in setOf("available", "restricted", "unavailable"))
                },
                optional(item, "raw_time_text", 1000))
        } }
        require(activities.map { it.id }.distinct().size == activities.size)
        val warnings = (0 until rawWarnings.length()).map {
            rawWarnings.getString(it).also { warning -> require(Regex("^[A-Z0-9_]{1,64}$").matches(warning)) }
        }
        // Validate every entry and warning before applying a business exclusion.
        return QmplusSnapshot(fetchedAt, courses, QmplusCourseworkPolicy.activities(activities), warnings, partial)
    }

    /** Re-encode only the business schema; never persist arbitrary webpage fields. */
    fun encode(snapshot: QmplusSnapshot): ByteArray = JSONObject().put("schema_version", 1).put("source", "qmplus")
        .put("ok", true).put("partial", snapshot.partial)
        .put("fetched_at", snapshot.fetchedAt)
        .put("courses", JSONArray().apply { snapshot.courses.forEach { course -> put(JSONObject()
            .put("id", course.id).put("name", course.name).nullable("short_name", course.shortName)
            .put("url", course.url).nullable("start_at", course.startAt).nullable("end_at", course.endAt)
            .put("current_term_status", course.currentTermStatus)) } })
        .put("activities", JSONArray().apply { snapshot.activities.forEach { item -> put(JSONObject()
            .put("id", item.id).put("course_id", item.courseID).put("title", item.title).put("kind", item.kind)
            .put("url", item.url).nullable("due_at", item.dueAt).nullable("opens_at", item.opensAt)
            .nullable("closes_at", item.closesAt).nullable("cutoff_at", item.cutoffAt)
            .nullable("time_limit_seconds", item.timeLimitSeconds).nullable("status", item.status)
            .nullable("detail_status", item.detailStatus).nullable("raw_time_text", item.rawTimeText)) } })
        .put("warnings", JSONArray(snapshot.warnings)).toString().toByteArray(StandardCharsets.UTF_8).also {
            require(it.size <= QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES)
        }

    fun preservingKnownActivities(incoming: QmplusSnapshot, previous: QmplusSnapshot?): QmplusSnapshot {
        if (!incoming.partial || previous == null)
            return incoming.copy(activities = QmplusCourseworkPolicy.activities(incoming.activities))
        val allCourses = (incoming.courses + previous.courses).distinctBy { it.id }
        val courses = allCourses.take(100)
        val ids = courses.map { it.id }.toSet()
        val allActivities = QmplusCourseworkPolicy.activities((incoming.activities + previous.activities).distinctBy { it.id })
            .filter { it.courseID in ids }
        val warnings = (if (allCourses.size > 100 || allActivities.size > 500) listOf("QM_NATIVE_CACHE_LIMIT") else emptyList()) +
            listOf("QM_PREVIOUS_ACTIVITIES_RETAINED") + incoming.warnings
        val boundedWarnings = warnings
            .distinct().take(40)
        return incoming.copy(courses = courses, activities = allActivities.take(500), warnings = boundedWarnings)
    }

    private fun JSONObject.nullable(key: String, value: Any?): JSONObject = put(key, value ?: JSONObject.NULL)
    private fun required(root: JSONObject, key: String, maximum: Int): String = root.getString(key).also {
        require(it.isNotBlank() && it.length <= maximum && '\u0000' !in it)
    }
    private fun optional(root: JSONObject, key: String, maximum: Int): String? =
        if (root.isNull(key)) null else root.getString(key).also { require(it.length <= maximum && '\u0000' !in it) }
    fun parseUTCDate(value: String): java.util.Date? {
        if (!Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,9})?Z$").matches(value)) return null
        val seconds = value.substringBefore('.').removeSuffix("Z") + "Z"
        val position = ParsePosition(0)
        val date = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            isLenient = false; timeZone = TimeZone.getTimeZone("UTC")
        }.parse(seconds, position) ?: return null
        if (position.index != seconds.length) return null
        val fraction = value.substringAfter('.', "").removeSuffix("Z")
        val milliseconds = if (fraction.isEmpty()) 0 else fraction.take(3).padEnd(3, '0').toInt()
        return java.util.Date(date.time + milliseconds)
    }
    private fun date(root: JSONObject, key: String): String? = optional(root, key, 40)?.also { value ->
        require(parseUTCDate(value) != null)
    }
    private fun validateNesting(text: String) {
        var depth = 0; var quoted = false; var escaped = false
        text.forEach { ch ->
            if (quoted) {
                if (escaped) escaped = false else if (ch == '\\') escaped = true else if (ch == '"') quoted = false
            } else when (ch) {
                '"' -> quoted = true
                '{', '[' -> { depth++; require(depth <= 12) }
                '}', ']' -> { depth--; require(depth >= 0) }
            }
        }
        require(depth == 0 && !quoted)
    }
}

internal object QmplusActivityPresentation {
    fun currentCourses(courses: List<QmplusCourse>): List<QmplusCourse> =
        courses.filter { it.currentTermStatus != "other" }

    fun displayTimeFields(item: QmplusActivityItem): List<Pair<String, String?>> =
        if (item.kind == "assignment") buildList {
            add("截止时间" to item.dueAt)
            item.cutoffAt?.let { add("最终提交时间" to it) }
        } else listOf("开放时间" to item.opensAt, "关闭时间" to item.closesAt)

    fun shanghaiTime(value: String?): String? = value?.let(QmplusSnapshotCodec::parseUTCDate)?.let { date ->
        SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(date)
    }

    fun timeFields(item: QmplusActivityItem): List<Pair<String, String>> =
        (if (item.kind == "assignment") listOf("due_at" to item.dueAt, "cutoff_at" to item.cutoffAt)
        else listOf("opens_at" to item.opensAt, "closes_at" to item.closesAt))
            .mapNotNull { (field, value) -> value?.let { field to it } }
}
