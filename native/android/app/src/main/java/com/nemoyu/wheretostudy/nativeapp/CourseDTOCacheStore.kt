package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONArray
import org.json.JSONObject

internal data class CourseDTOCache(
    val scope: String,
    val courses: List<TeachingCloudCourse>?,
    val assignments: List<AssignmentDeadlineItem>?,
    val coursesFetchedAt: Long,
    val assignmentsFetchedAt: Long,
)

// Business DTOs only: the binding is random metadata from the protected record,
// never an account, credential digest, cookie, token, ticket or captured HTML.
internal class CourseDTOCacheStore(context: Context) {
    private val file = File(context.applicationContext.noBackupFilesDir, "teaching-cloud-dto-v1.json")
    private val lock = locks.getOrPut(file.absolutePath) { Any() }

    fun load(scope: String): CourseDTOCache? = synchronized(lock) {
        if (!scopePattern.matches(scope)) return@synchronized null
        runCatching {
            val atomic = AtomicFile(file)
            atomic.openRead().use { stream ->
                val bytes = ByteArray(MAXIMUM_BYTES + 1)
                var size = 0
                while (size < bytes.size) {
                    val count = stream.read(bytes, size, bytes.size - size)
                    if (count < 0) break
                    size += count
                }
                require(size <= MAXIMUM_BYTES)
                decode(JSONObject(String(bytes, 0, size, Charsets.UTF_8)), scope)
            }
        }.getOrNull()
    }

    fun save(cache: CourseDTOCache, current: () -> Boolean): Boolean = synchronized(lock) {
        if (!current()) return@synchronized false
        val root = JSONObject().put("schema", 1).put("source", "teaching-cloud").put("scope", cache.scope)
            .put("courses_fetched_at", cache.coursesFetchedAt).put("assignments_fetched_at", cache.assignmentsFetchedAt)
            .put("courses", cache.courses?.let { courses -> JSONArray(courses.map { course ->
                JSONObject().put("id", course.id).put("name", course.name ?: JSONObject.NULL)
                    .put("teachers", JSONArray(course.teacherNames))
            }) } ?: JSONObject.NULL)
            .put("assignments", cache.assignments?.let { items -> JSONArray(items.map { item ->
                JSONObject().put("id", item.id).put("title", item.title)
                    .put("course_name", item.courseName ?: JSONObject.NULL).put("course_id", item.courseID ?: JSONObject.NULL)
                    .put("deadline", item.deadline).put("status", item.status ?: JSONObject.NULL)
            }) } ?: JSONObject.NULL)
        decode(root, cache.scope)
        val bytes = root.toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAXIMUM_BYTES)
        if (!current()) return@synchronized false
        file.parentFile?.mkdirs()
        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try { output.write(bytes); atomic.finishWrite(output) } catch (error: Exception) {
            atomic.failWrite(output); throw error
        }
        current()
    }

    fun clear() = synchronized(lock) {
        AtomicFile(file).delete()
        check(!file.exists() && !File(file.absolutePath + ".bak").exists() && !File(file.absolutePath + ".new").exists()) {
            "COURSE_CACHE_CLEAR_FAILED"
        }
    }

    private fun decode(root: JSONObject, scope: String): CourseDTOCache {
        keys(root, setOf("schema", "source", "scope", "courses", "assignments", "courses_fetched_at", "assignments_fetched_at"))
        require(root.get("schema") == 1 && root.get("source") == "teaching-cloud" &&
            root.get("scope") == scope && scopePattern.matches(scope))
        val courses = if (root.isNull("courses")) null else root.getJSONArray("courses").let { rows ->
            require(rows.length() <= 512)
            val ids = mutableSetOf<String>()
            List(rows.length()) { index ->
                val row = rows.getJSONObject(index); keys(row, setOf("id", "name", "teachers"))
                val id = text(row, "id", 128)!!; require(id.isNotEmpty() && ids.add(id))
                val names = row.getJSONArray("teachers"); require(names.length() <= 64)
                val teachers = List(names.length()) { teacher ->
                    (names.get(teacher) as? String)?.takeIf { it.length <= 256 } ?: error("COURSE_CACHE_TEXT")
                }
                TeachingCloudCourse(id, text(row, "name", nullable = true), teachers.firstOrNull(), teachers)
            }
        }
        val assignments = if (root.isNull("assignments")) null else root.getJSONArray("assignments").let { rows ->
            require(rows.length() <= 5000)
            val ids = mutableSetOf<String>()
            List(rows.length()) { index ->
                val row = rows.getJSONObject(index); keys(row, setOf("id", "title", "course_name", "course_id", "deadline", "status"))
                val id = text(row, "id", 256)!!; require(id.isNotEmpty() && ids.add(id))
                val deadline = text(row, "deadline", 64)!!
                require(validDeadlineDate(deadline))
                AssignmentDeadlineItem(id, text(row, "title")!!, text(row, "course_name", nullable = true), deadline,
                    text(row, "status", nullable = true), text(row, "course_id", 128, true))
            }
        }
        fun timestamp(key: String): Long {
            val value = root.get(key) as? Number ?: error("COURSE_CACHE_TIME")
            val number = value.toDouble()
            require(number.isFinite() && number >= 0 && number <= System.currentTimeMillis() + 60_000 && number == value.toLong().toDouble())
            return value.toLong()
        }
        return CourseDTOCache(scope, courses, assignments, timestamp("courses_fetched_at"), timestamp("assignments_fetched_at"))
    }

    private fun text(row: JSONObject, key: String, maximum: Int = 2048, nullable: Boolean = false): String? {
        if (nullable && row.isNull(key)) return null
        return (row.get(key) as? String)?.takeIf { it.length <= maximum } ?: error("COURSE_CACHE_TEXT")
    }
    private fun keys(row: JSONObject, allowed: Set<String>) {
        require(row.keys().asSequence().toSet() == allowed)
    }
    companion object {
        fun validDeadlineDate(deadline: String): Boolean {
            if (!deadlinePattern.matches(deadline)) return false
            val day = deadline.take(10)
            val position = java.text.ParsePosition(0)
            return java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply {
                isLenient = false; timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.parse(day, position) != null && position.index == day.length
        }
        private const val MAXIMUM_BYTES = 2 * 1024 * 1024
        private val locks = ConcurrentHashMap<String, Any>()
        private val scopePattern = Regex("^[0-9a-f]{32}$")
        private val deadlinePattern = Regex("^\\d{4}-\\d{2}-\\d{2}[ T](?:[01]\\d|2[0-3]):[0-5]\\d(?::[0-5]\\d(?:\\.\\d{1,3})?)?(?:Z|[+-](?:[01]\\d|2[0-3]):[0-5]\\d)?$")
    }
}
