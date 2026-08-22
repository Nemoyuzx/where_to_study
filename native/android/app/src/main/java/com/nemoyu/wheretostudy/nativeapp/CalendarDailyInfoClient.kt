package com.nemoyu.wheretostudy.nativeapp

import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject

data class AlmanacInfo(
    val date: String,
    val weekday: String,
    val lunarDate: String,
    val ganzhiYear: String,
    val ganzhiMonth: String,
    val ganzhiDay: String,
    val zodiac: String,
    val solarTerm: String?,
    val lunarFestival: String?,
    val solarFestival: String?,
    val yi: String?,
    val ji: String?,
)

enum class PublicDeadlineKind(val wireValue: String, val title: String) {
    COMPETITION("competition", "学科竞赛"),
    SUMMER_CAMP("summer_camp", "夏令营"),
    HACKATHON("hackathon", "黑客松");

    companion object {
        fun fromWireValue(value: String): PublicDeadlineKind? =
            entries.firstOrNull { it.wireValue == value }
    }
}

enum class PublicDeadlineSource(val wireValue: String, val title: String) {
    CONTEST_DDL("contest_ddl", "Contest DDL"),
    SCHOOL_NOTICE("school_notice", "校内竞赛通知"),
}

data class PublicDeadlineItem(
    val id: String,
    val name: String,
    val kind: PublicDeadlineKind,
    val source: PublicDeadlineSource,
    val deadline: String,
    val organizer: String?,
    val officialURL: String?,
)

data class PublicDeadlineSnapshot(
    val date: String,
    val items: List<PublicDeadlineItem>,
    val source: String,
    val usedBackup: Boolean,
)

data class AssignmentDeadlineItem(
    val id: String,
    val title: String,
    val courseName: String?,
    val deadline: String,
    val status: String?,
)

internal object CalendarDailyInfoSources {
    const val uapiOrigin = "https://uapis.cn"
    const val timelessOrigin = "https://api.timelessq.com"
    const val deadlinePrimary =
        "https://nemoyuzx.github.io/contest-ddl/data/competitions.json"
    const val deadlinePrimaryPage = "https://nemoyuzx.github.io/contest-ddl/"
    const val deadlineBackup = "http://101.201.29.29/api/contest-events"
    const val schoolContestNotices = "http://101.201.29.29/api/contest-notices"
    const val assignments =
        "https://ucloud.bupt.edu.cn/uclass/course.html#/student/studentAssignmentListPage?ind=3"
    const val smallPayloadLimit = 128 * 1024
    const val deadlinePayloadLimit = 2 * 1024 * 1024
}

internal object AlmanacResponseParser {
    fun parseBase(payload: String, requestedDate: String): AlmanacInfo {
        requireContractDate(requestedDate, "黄历")
        val source = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("黄历数据格式不正确。", error)
        }
        val datetime = requiredString(source, "datetime", "黄历数据格式不正确。")
        if (!datetime.startsWith(requestedDate)) {
            throw DailyInfoClientException("黄历数据日期不一致。")
        }
        return AlmanacInfo(
            date = requestedDate,
            weekday = requiredString(source, "weekday_cn", "黄历数据格式不正确。"),
            lunarDate = requiredString(source, "lunar_month_cn", "黄历数据格式不正确。") +
                requiredString(source, "lunar_day_cn", "黄历数据格式不正确。"),
            ganzhiYear = requiredString(source, "ganzhi_year", "黄历数据格式不正确。"),
            ganzhiMonth = requiredString(source, "ganzhi_month", "黄历数据格式不正确。"),
            ganzhiDay = requiredString(source, "ganzhi_day", "黄历数据格式不正确。"),
            zodiac = requiredString(source, "zodiac", "黄历数据格式不正确。"),
            solarTerm = optionalString(source, "solar_term"),
            lunarFestival = optionalString(source, "lunar_festival"),
            solarFestival = optionalString(source, "solar_festival"),
            yi = null,
            ji = null,
        )
    }

    fun parseAdvice(payload: String, requestedDate: String): Pair<String, String> {
        val requested = requireContractDate(requestedDate, "宜忌")
        val source = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("宜忌数据格式不正确。", error)
        }
        if (source.optInt("errno", -1) != 0) {
            throw DailyInfoClientException(
                optionalString(source, "errmsg") ?: "宜忌接口返回错误。",
            )
        }
        val data = source.optJSONObject("data")
            ?: throw DailyInfoClientException("宜忌数据格式不正确。")
        if (data.optInt("year") != requested.get(Calendar.YEAR) ||
            data.optInt("month") != requested.get(Calendar.MONTH) + 1 ||
            data.optInt("day") != requested.get(Calendar.DAY_OF_MONTH)
        ) {
            throw DailyInfoClientException("宜忌数据日期不一致。")
        }
        val almanac = data.optJSONObject("almanac")
            ?: throw DailyInfoClientException("宜忌数据格式不正确。")
        return requiredString(almanac, "yi", "宜忌数据格式不正确。") to
            requiredString(almanac, "ji", "宜忌数据格式不正确。")
    }
}

internal object PublicDeadlineResponseParser {
    private val rfc3339 = Regex(
        "^\\d{4}-\\d{2}-\\d{2}T(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d" +
            "(?:\\.\\d+)?(?:Z|[+-](?:[01]\\d|2[0-3]):[0-5]\\d)$",
    )

    fun parse(payload: String, requestedDate: String): List<PublicDeadlineItem> {
        requireContractDate(requestedDate, "DDL")
        val root: Any = try {
            val trimmed = payload.trimStart()
            if (trimmed.startsWith("[")) JSONArray(payload) else JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("DDL 数据格式不正确。", error)
        }
        val records = extractRecords(root)
        return (0 until records.length()).mapNotNull { index ->
            val record = records.optJSONObject(index) ?: return@mapNotNull null
            val kind = PublicDeadlineKind.fromWireValue(
                firstString(record, "event_type", "eventType", "type")
                    ?: return@mapNotNull null,
            ) ?: return@mapNotNull null
            val id = firstString(record, "id", "event_id", "eventId")
                ?: return@mapNotNull null
            val name = firstString(record, "name", "title", "event_name")
                ?: return@mapNotNull null
            val deadline = firstString(
                record,
                "primary_deadline",
                "primaryDeadline",
                "deadline",
                "end_time",
            ) ?: return@mapNotNull null
            if (!deadline.startsWith(requestedDate) || !rfc3339.matches(deadline)) {
                return@mapNotNull null
            }
            val officialURL = firstString(record, "official_url", "officialUrl", "url")
                ?.takeIf(::isTrustedOfficialURL)
            PublicDeadlineItem(
                id = id,
                name = name,
                kind = kind,
                source = PublicDeadlineSource.CONTEST_DDL,
                deadline = deadline,
                organizer = firstString(record, "organizer", "host"),
                officialURL = officialURL,
            )
        }
            .take(100)
            .sortedWith(compareBy(PublicDeadlineItem::deadline, PublicDeadlineItem::name))
    }

    fun parseSchoolNotices(payload: String, requestedDate: String): List<PublicDeadlineItem> {
        requireContractDate(requestedDate, "DDL")
        val source = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("校内竞赛通知格式不正确。", error)
        }
        val records = source.optJSONArray("items") ?: JSONArray()
        val result = mutableListOf<PublicDeadlineItem>()
        for (recordIndex in 0 until records.length()) {
            val record = records.optJSONObject(recordIndex) ?: continue
            val id = firstString(record, "id", "source_id") ?: continue
            val name = firstString(record, "name", "title") ?: continue
            val sourceName = firstString(record, "source")
                ?: "北京邮电大学教学云平台"
            val officialURL = firstString(record, "source_url")
                ?.takeIf(::isTrustedOfficialURL)
            val sourceDeadlines = record.optJSONArray("deadlines")
            val deadlines = if (sourceDeadlines == null || sourceDeadlines.length() == 0) {
                val primary = firstString(record, "primary_deadline") ?: continue
                JSONArray().put(JSONObject().apply {
                    put("date", primary)
                    put(
                        "label",
                        firstString(record, "primary_deadline_label") ?: "截止时间",
                    )
                })
            } else sourceDeadlines
            for (deadlineIndex in 0 until deadlines.length()) {
                val deadlineRecord = deadlines.optJSONObject(deadlineIndex) ?: continue
                val deadline = firstString(deadlineRecord, "date") ?: continue
                if (!deadline.startsWith(requestedDate) || !rfc3339.matches(deadline)) continue
                val label = firstString(deadlineRecord, "label") ?: "截止时间"
                result += PublicDeadlineItem(
                    id = "school:$id:$deadlineIndex",
                    name = name,
                    kind = PublicDeadlineKind.COMPETITION,
                    source = PublicDeadlineSource.SCHOOL_NOTICE,
                    deadline = deadline,
                    organizer = "$sourceName · $label",
                    officialURL = officialURL,
                )
                if (result.size >= 100) break
            }
            if (result.size >= 100) break
        }
        return result.sortedWith(compareBy(PublicDeadlineItem::deadline, PublicDeadlineItem::name))
    }

    fun merge(vararg groups: List<PublicDeadlineItem>): List<PublicDeadlineItem> {
        val unique = linkedMapOf<String, PublicDeadlineItem>()
        groups.forEach { group ->
            group.forEach { item ->
                val key = listOf(
                    item.source.wireValue,
                    item.kind.wireValue,
                    item.name.trim().lowercase(),
                    item.deadline,
                ).joinToString("\u001f")
                unique.putIfAbsent(key, item)
            }
        }
        return unique.values
            .sortedWith(compareBy(PublicDeadlineItem::deadline, PublicDeadlineItem::name))
            .take(100)
    }

    private fun extractRecords(root: Any): JSONArray {
        if (root is JSONArray) return root
        val source = root as? JSONObject ?: return JSONArray()
        listOf("items", "records", "data").forEach { key ->
            when (val value = source.opt(key)) {
                is JSONArray -> return value
                is JSONObject -> {
                    value.optJSONArray("items")?.let { return it }
                    value.optJSONArray("records")?.let { return it }
                }
            }
        }
        return JSONArray()
    }

    private fun isTrustedOfficialURL(value: String): Boolean = runCatching {
        val uri = URI.create(value)
        uri.scheme.equals("https", ignoreCase = true) &&
            !uri.host.isNullOrBlank() && uri.userInfo == null
    }.getOrDefault(false)
}

internal object AssignmentDeadlineResponseParser {
    fun parse(payload: String, requestedDate: String): List<AssignmentDeadlineItem> {
        requireContractDate(requestedDate, "作业")
        val source = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("作业数据格式不正确。", error)
        }
        return parseAll(source, null)
            .filter { it.deadline.startsWith(requestedDate) }
            .sortedWith(compareBy(AssignmentDeadlineItem::deadline, AssignmentDeadlineItem::title))
    }

    fun parseAll(
        source: JSONObject,
        courseNameOverride: String?,
    ): List<AssignmentDeadlineItem> {
        val firstData = source.optJSONObject("data") ?: source
        val secondData = firstData.optJSONObject("data") ?: firstData
        val records = secondData.optJSONArray("records")
            ?: secondData.optJSONArray("undoneList")
            ?: JSONArray()
        return (0 until records.length()).mapNotNull { index ->
            val item = records.optJSONObject(index) ?: return@mapNotNull null
            if (item.has("type") && item.optInt("type", -1) !in listOf(3, 5)) {
                return@mapNotNull null
            }
            val deadline = firstString(item, "assignmentEndTime", "endTime")
                ?: return@mapNotNull null
            if (!isAssignmentTimestamp(deadline)) {
                return@mapNotNull null
            }
            val id = firstString(item, "id", "assignmentId", "activityId")
                ?: return@mapNotNull null
            val title = firstString(item, "assignmentTitle", "activityName", "title")
                ?: return@mapNotNull null
            AssignmentDeadlineItem(
                id = id,
                title = title,
                courseName = firstString(item, "siteName", "courseName", "siteTitle")
                    ?: courseNameOverride?.trim()?.takeIf(String::isNotEmpty),
                deadline = deadline,
                status = when (item.optInt("assignmentStatus", Int.MIN_VALUE)) {
                    99 -> "未提交"
                    0 -> "已提交"
                    1 -> "已批改"
                    2 -> "已驳回"
                    else -> optionalString(item, "assignmentStatus")
                },
            )
        }
    }

    private fun isAssignmentTimestamp(value: String): Boolean =
        Regex("^\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}(?::\\d{2})?(?:.*)?$")
            .matches(value)
}

class CalendarDailyInfoClient {
    fun fetchAlmanac(date: String): AlmanacInfo {
        val target = requireContractDate(date, "黄历")
        target.set(Calendar.HOUR_OF_DAY, 12)
        val timestamp = target.timeInMillis / 1_000L
        val basePayload = FixedPublicJsonTransport.fetch(
            URI.create(
                "${CalendarDailyInfoSources.uapiOrigin}/api/v1/misc/lunartime" +
                    "?ts=$timestamp&timezone=Asia/Shanghai",
            ),
            "https",
            "uapis.cn",
            CalendarDailyInfoSources.smallPayloadLimit,
        )
        val base = AlmanacResponseParser.parseBase(basePayload, date)
        return runCatching {
            val advicePayload = FixedPublicJsonTransport.fetch(
                URI.create("${CalendarDailyInfoSources.timelessOrigin}/time?datetime=$date"),
                "https",
                "api.timelessq.com",
                CalendarDailyInfoSources.smallPayloadLimit,
            )
            val advice = AlmanacResponseParser.parseAdvice(advicePayload, date)
            base.copy(yi = advice.first, ji = advice.second)
        }.getOrDefault(base)
    }

    fun fetchDeadlines(date: String): PublicDeadlineSnapshot {
        requireContractDate(date, "DDL")
        val contestResult = runCatching {
            val payload = FixedPublicJsonTransport.fetch(
                URI.create(CalendarDailyInfoSources.deadlinePrimary),
                "https",
                "nemoyuzx.github.io",
                CalendarDailyInfoSources.deadlinePayloadLimit,
            )
            PublicDeadlineSnapshot(
                date,
                PublicDeadlineResponseParser.parse(payload, date),
                CalendarDailyInfoSources.deadlinePrimary,
                false,
            )
        }.recoverCatching { primaryError ->
            try {
                val payload = FixedPublicJsonTransport.fetch(
                    URI.create(CalendarDailyInfoSources.deadlineBackup),
                    "http",
                    "101.201.29.29",
                    CalendarDailyInfoSources.deadlinePayloadLimit,
                )
                PublicDeadlineSnapshot(
                    date,
                    PublicDeadlineResponseParser.parse(payload, date),
                    CalendarDailyInfoSources.deadlineBackup,
                    true,
                )
            } catch (backupError: Exception) {
                throw DailyInfoClientException(
                    "主 DDL 数据源不可用（${primaryError.message}）；" +
                        "备用数据源也不可用（${backupError.message}）。",
                    backupError,
                )
            }
        }
        val schoolResult = runCatching {
            val payload = FixedPublicJsonTransport.fetch(
                URI.create(CalendarDailyInfoSources.schoolContestNotices),
                "http",
                "101.201.29.29",
                CalendarDailyInfoSources.deadlinePayloadLimit,
            )
            PublicDeadlineResponseParser.parseSchoolNotices(payload, date)
        }
        val contest = contestResult.getOrNull()
        val schoolItems = schoolResult.getOrNull()
        if (contest == null && schoolItems == null) {
            throw DailyInfoClientException(
                "公开活动 DDL 不可用（${contestResult.exceptionOrNull()?.message}）；" +
                    "校内竞赛通知也不可用（${schoolResult.exceptionOrNull()?.message}）。",
                schoolResult.exceptionOrNull(),
            )
        }
        if (contest == null) {
            return PublicDeadlineSnapshot(
                date = date,
                items = schoolItems.orEmpty(),
                source = CalendarDailyInfoSources.schoolContestNotices,
                usedBackup = false,
            )
        }
        if (schoolItems == null) return contest
        return PublicDeadlineSnapshot(
            date = date,
            items = PublicDeadlineResponseParser.merge(contest.items, schoolItems),
            source = contest.source,
            usedBackup = contest.usedBackup,
        )
    }
}

private object FixedPublicJsonTransport {
    fun fetch(uri: URI, scheme: String, host: String, maximumBytes: Int): String {
        val defaultPort = if (scheme == "https") 443 else 80
        val effectivePort = if (uri.port == -1) defaultPort else uri.port
        if (!uri.scheme.equals(scheme, ignoreCase = true) ||
            !uri.host.equals(host, ignoreCase = true) ||
            effectivePort != defaultPort || uri.userInfo != null
        ) {
            throw DailyInfoClientException("公开数据源地址不受信任。")
        }
        val connection = uri.toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty(
                "User-Agent",
                "WhereToStudyNative/${BuildConfig.VERSION_NAME}",
            )
            val status = connection.responseCode
            if (status in 300..399) {
                throw DailyInfoClientException("公开数据源返回了不受信任的重定向。")
            }
            if (status !in 200..299) {
                throw DailyInfoClientException("公开数据源返回错误，HTTP $status。")
            }
            if (connection.contentLengthLong > maximumBytes) {
                throw DailyInfoClientException("公开数据响应过大。")
            }
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            connection.inputStream.use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    if (output.size() + count > maximumBytes) {
                        throw DailyInfoClientException("公开数据响应过大。")
                    }
                    output.write(buffer, 0, count)
                }
            }
            return output.toString(StandardCharsets.UTF_8.name())
        } finally {
            connection.disconnect()
        }
    }
}

internal class CalendarDailyInfoRepository(
    private val client: CalendarDailyInfoClient = CalendarDailyInfoClient(),
    private val assignmentClient: UCloudAssignmentClient? = null,
    private val usesSampleData: Boolean = DailyCourseNotificationRuntimeMode.isUiTesting,
) {
    private val worker = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val almanacByDate = ConcurrentHashMap<String, AlmanacInfo>()
    private val almanacErrors = ConcurrentHashMap<String, String>()
    private val loadingAlmanac = ConcurrentHashMap.newKeySet<String>()
    private val deadlinesByDate = ConcurrentHashMap<String, PublicDeadlineSnapshot>()
    private val deadlineErrors = ConcurrentHashMap<String, String>()
    private val loadingDeadlines = ConcurrentHashMap.newKeySet<String>()
    private val assignmentsByDate = ConcurrentHashMap<String, List<AssignmentDeadlineItem>>()
    private val assignmentErrors = ConcurrentHashMap<String, String>()
    private val loadingAssignments = ConcurrentHashMap.newKeySet<String>()
    private val assignmentRevision = AtomicLong(0)
    private val closed = AtomicBoolean(false)

    fun almanac(date: String): AlmanacInfo? = almanacByDate[date]
    fun almanacError(date: String): String? = almanacErrors[date]
    fun isLoadingAlmanac(date: String): Boolean = date in loadingAlmanac
    fun deadlines(date: String): PublicDeadlineSnapshot? = deadlinesByDate[date]
    fun deadlineError(date: String): String? = deadlineErrors[date]
    fun isLoadingDeadlines(date: String): Boolean = date in loadingDeadlines
    fun assignments(date: String): List<AssignmentDeadlineItem>? = assignmentsByDate[date]
    fun assignmentError(date: String): String? = assignmentErrors[date]
    fun isLoadingAssignments(date: String): Boolean = date in loadingAssignments

    fun loadAlmanac(date: String, force: Boolean = false, onComplete: () -> Unit) {
        if (closed.get() || (!force && almanacByDate[date] != null) || !loadingAlmanac.add(date)) {
            return
        }
        almanacErrors.remove(date)
        try {
            worker.execute {
                runCatching {
                    if (usesSampleData) sampleAlmanac(date) else client.fetchAlmanac(date)
                }.onSuccess { almanacByDate[date] = it }
                    .onFailure { almanacErrors[date] = it.message ?: "黄历获取失败。" }
                loadingAlmanac.remove(date)
                postCompletion(onComplete)
            }
        } catch (_: RejectedExecutionException) {
            loadingAlmanac.remove(date)
        }
    }

    fun loadDeadlines(date: String, force: Boolean = false, onComplete: () -> Unit) {
        if (closed.get() || (!force && deadlinesByDate[date] != null) ||
            !loadingDeadlines.add(date)
        ) {
            return
        }
        deadlineErrors.remove(date)
        try {
            worker.execute {
                runCatching {
                    if (usesSampleData) sampleDeadlines(date) else client.fetchDeadlines(date)
                }.onSuccess { deadlinesByDate[date] = it }
                    .onFailure { deadlineErrors[date] = it.message ?: "DDL 获取失败。" }
                loadingDeadlines.remove(date)
                postCompletion(onComplete)
            }
        } catch (_: RejectedExecutionException) {
            loadingDeadlines.remove(date)
        }
    }

    fun loadAssignments(date: String, force: Boolean = false, onComplete: () -> Unit) {
        if (closed.get() || (!force && assignmentsByDate[date] != null) ||
            !loadingAssignments.add(date)
        ) {
            return
        }
        assignmentErrors.remove(date)
        val requestRevision = assignmentRevision.get()
        try {
            worker.execute {
                runCatching {
                    when {
                        usesSampleData -> sampleAssignments(date)
                        assignmentClient != null -> assignmentClient.fetch(date)
                        else -> throw DailyInfoClientException("请先在设置中保存教务账号和密码。")
                    }
                }.onSuccess {
                    if (assignmentRevision.get() == requestRevision) {
                        assignmentsByDate[date] = it
                    }
                }.onFailure {
                    if (assignmentRevision.get() == requestRevision) {
                        assignmentErrors[date] = it.message ?: "课程作业获取失败。"
                    }
                }
                if (assignmentRevision.get() == requestRevision) {
                    loadingAssignments.remove(date)
                    postCompletion(onComplete)
                }
            }
        } catch (_: RejectedExecutionException) {
            loadingAssignments.remove(date)
        }
    }

    fun clearAssignments() {
        assignmentRevision.incrementAndGet()
        assignmentsByDate.clear()
        assignmentErrors.clear()
        loadingAssignments.clear()
        assignmentClient?.reset()
    }

    private fun postCompletion(onComplete: () -> Unit) {
        if (!closed.get()) mainHandler.post { if (!closed.get()) onComplete() }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        clearAssignments()
        mainHandler.removeCallbacksAndMessages(null)
        worker.shutdownNow()
    }

    private fun sampleAlmanac(date: String) = AlmanacInfo(
        date,
        "星期六",
        "七月初十",
        "丙午",
        "丙申",
        "戊辰",
        "马",
        null,
        null,
        null,
        "学习、交流、制定计划",
        "拖延、熬夜",
    )

    private fun sampleDeadlines(date: String) = PublicDeadlineSnapshot(
        date,
        listOf(PublicDeadlineItem(
            "sample-competition",
            "全国大学生示例竞赛",
            PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.CONTEST_DDL,
            "${date}T23:59:00+08:00",
            "示例组委会",
            null,
        )),
        CalendarDailyInfoSources.deadlinePrimary,
        false,
    )

    private fun sampleAssignments(date: String) = listOf(AssignmentDeadlineItem(
        "sample-assignment",
        "示例课程作业",
        "示例课程",
        "$date 23:59:00",
        "未提交",
    ))
}

private fun requireContractDate(value: String, label: String): Calendar {
    if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) {
        throw DailyInfoClientException("$label 日期格式不正确。")
    }
    return runCatching {
        Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
            isLenient = false
            val parts = value.split('-').map(String::toInt)
            set(parts[0], parts[1] - 1, parts[2], 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
            timeInMillis
        }
    }.getOrElse { throw DailyInfoClientException("$label 日期格式不正确。", it) }
}

private fun requiredString(source: JSONObject, key: String, message: String): String =
    optionalString(source, key) ?: throw DailyInfoClientException(message)

private fun optionalString(source: JSONObject, key: String): String? = when (val value = source.opt(key)) {
    null, JSONObject.NULL -> null
    is String -> value.trim().takeIf(String::isNotEmpty)
    is Number -> value.toString()
    else -> null
}

private fun firstString(source: JSONObject, vararg keys: String): String? =
    keys.firstNotNullOfOrNull { optionalString(source, it) }
