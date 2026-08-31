package com.nemoyu.wheretostudy.nativeapp

import android.os.Handler
import android.os.Looper
import java.net.URI
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

data class ShuttleBusService(
    val vehicle: String,
    val count: Int,
)

data class ShuttleBusRow(
    val departureTime: String,
    val services: Map<String, ShuttleBusService?>,
)

data class ShuttleBusPeriod(
    val label: String,
    val startDate: String?,
    val endDate: String?,
)

data class ShuttleBusSchedule(
    val period: ShuttleBusPeriod,
    val from: String?,
    val to: String?,
    val parseStatus: String,
    val rows: List<ShuttleBusRow>,
)

data class ShuttleBusNotice(
    val id: String,
    val title: String,
    val publishedAt: String,
    val sourceURL: String?,
    val kind: String,
    val parseStatus: String,
    val stops: List<Pair<String, String>>,
    val notes: List<String>,
    val schedules: List<ShuttleBusSchedule>,
)

data class ShuttleBusSnapshot(
    val generatedAt: String,
    val status: String,
    val sourceName: String,
    val sourcePage: String,
    val notices: List<ShuttleBusNotice>,
)

data class TodayShuttleDeparture(
    val time: String,
    val vehicle: String,
    val count: Int,
)

data class TodayShuttleRoute(
    val from: String,
    val to: String,
    val periodLabel: String,
    val departures: List<TodayShuttleDeparture>,
)

data class TodayShuttlePresentation(
    val status: String,
    val nextDeparture: String?,
    val noticeTitle: String?,
    val noticeURL: String?,
    val stops: List<Pair<String, String>>,
    val notes: List<String>,
    val routes: List<TodayShuttleRoute>,
    val isStale: Boolean,
)

internal object ShuttleBusResponseParser {
    private val weekdays = setOf(
        "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday",
    )
    private val timePattern = Regex("^(?:[01]\\d|2[0-3]):[0-5]\\d$")

    fun parse(payload: String): ShuttleBusSnapshot {
        val root = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("班车数据格式不正确。", error)
        }
        if (root.optString("schema_version") != "1.0") {
            throw DailyInfoClientException("班车数据版本不受支持。")
        }
        val source = root.optJSONObject("source")
            ?: throw DailyInfoClientException("班车数据缺少来源。")
        val sourceName = requiredString(source, "name", 100)
        val sourcePage = trustedURL(requiredString(source, "page_url", 500))
            ?: throw DailyInfoClientException("班车来源地址不受信任。")
        val records = root.optJSONArray("items")
            ?: throw DailyInfoClientException("班车数据格式不正确。")
        if (records.length() > 100) throw DailyInfoClientException("班车通知数量异常。")
        val notices = buildList {
            for (index in 0 until records.length()) {
                val record = records.optJSONObject(index) ?: continue
                parseNotice(record)?.let(::add)
            }
        }.sortedWith(compareByDescending(ShuttleBusNotice::publishedAt).thenBy { it.id })
        return ShuttleBusSnapshot(
            generatedAt = requiredString(root, "generated_at", 80),
            status = requiredString(root, "status", 30).takeIf { it in setOf("healthy", "stale") }
                ?: throw DailyInfoClientException("班车服务状态无效。"),
            sourceName = sourceName,
            sourcePage = sourcePage,
            notices = notices,
        )
    }

    private fun parseNotice(record: JSONObject): ShuttleBusNotice? {
        val id = optionalString(record, "id", 160) ?: return null
        val title = optionalString(record, "title", 300) ?: return null
        val publishedAt = optionalString(record, "published_at", 10)
            ?.takeIf(StrictContractDate::isValid) ?: return null
        val schedules = record.optJSONArray("schedules")?.let { values ->
            buildList {
                for (index in 0 until minOf(values.length(), 24)) {
                    values.optJSONObject(index)?.let(::parseSchedule)?.let(::add)
                }
            }
        }.orEmpty()
        val stops = record.optJSONArray("stops")?.let { values ->
            buildList {
                for (index in 0 until minOf(values.length(), 12)) {
                    val stop = values.optJSONObject(index) ?: continue
                    val campus = optionalString(stop, "campus", 80) ?: continue
                    val location = optionalString(stop, "location", 160) ?: continue
                    add(campus to location)
                }
            }
        }.orEmpty()
        val notes = record.optJSONArray("notes")?.let { values ->
            buildList {
                for (index in 0 until minOf(values.length(), 8)) {
                    values.optString(index).trim()
                        .takeIf { it.isNotEmpty() && it.length <= 300 }
                        ?.let(::add)
                }
            }
        }.orEmpty()
        return ShuttleBusNotice(
            id = id,
            title = title,
            publishedAt = publishedAt,
            sourceURL = optionalString(record, "source_url", 500)?.let(::trustedURL),
            kind = optionalString(record, "kind", 40).orEmpty(),
            parseStatus = optionalString(record, "parse_status", 40).orEmpty(),
            stops = stops,
            notes = notes,
            schedules = schedules,
        )
    }

    private fun parseSchedule(record: JSONObject): ShuttleBusSchedule? {
        val periodRecord = record.optJSONObject("period") ?: JSONObject()
        val startDate = optionalString(periodRecord, "start_date", 10)
            ?.takeIf(StrictContractDate::isValid)
        val endDate = optionalString(periodRecord, "end_date", 10)
            ?.takeIf(StrictContractDate::isValid)
        if (startDate != null && endDate != null && endDate < startDate) return null
        val rows = record.optJSONArray("rows")?.let { values ->
            buildList {
                for (index in 0 until minOf(values.length(), 100)) {
                    values.optJSONObject(index)?.let(::parseRow)?.let(::add)
                }
            }
        }.orEmpty().sortedBy(ShuttleBusRow::departureTime)
        return ShuttleBusSchedule(
            period = ShuttleBusPeriod(
                label = optionalString(periodRecord, "label", 160) ?: "通知所示时段",
                startDate = startDate,
                endDate = endDate,
            ),
            from = optionalString(record, "from", 80),
            to = optionalString(record, "to", 80),
            parseStatus = optionalString(record, "parse_status", 40).orEmpty(),
            rows = rows,
        )
    }

    private fun parseRow(record: JSONObject): ShuttleBusRow? {
        val departureTime = optionalString(record, "departure_time", 5)
            ?.takeIf(timePattern::matches) ?: return null
        val servicesRecord = record.optJSONObject("services") ?: return null
        val services = weekdays.associateWith { weekday ->
            when (val value = servicesRecord.opt(weekday)) {
                null, JSONObject.NULL -> null
                is JSONObject -> {
                    val vehicle = optionalString(value, "vehicle", 40) ?: return@associateWith null
                    val count = value.optInt("count", 0)
                    if (count !in 1..20) null else ShuttleBusService(vehicle, count)
                }
                else -> null
            }
        }
        return ShuttleBusRow(departureTime, services)
    }

    private fun requiredString(source: JSONObject, key: String, maximum: Int): String =
        optionalString(source, key, maximum)
            ?: throw DailyInfoClientException("班车数据格式不正确。")

    private fun optionalString(source: JSONObject, key: String, maximum: Int): String? =
        (source.opt(key) as? String)?.trim()
            ?.takeIf { it.isNotEmpty() && it.length <= maximum }

    private fun trustedURL(value: String): String? = runCatching {
        val uri = URI.create(value)
        value.takeIf {
            uri.scheme.equals("https", ignoreCase = true) &&
                !uri.host.isNullOrBlank() && uri.userInfo == null
        }
    }.getOrNull()
}

internal object ShuttleBusLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun today(snapshot: ShuttleBusSnapshot, now: Calendar): TodayShuttlePresentation {
        val localNow = Calendar.getInstance(shanghai).apply { timeInMillis = now.timeInMillis }
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = shanghai
        }.format(localNow.time)
        val weekday = weekdayKey(localNow.get(Calendar.DAY_OF_WEEK))
        val selection = selectCurrentNotice(snapshot.notices, today)
        val notice = selection?.first
        val routes = selection?.second.orEmpty().mapNotNull { schedule ->
            val from = schedule.from ?: return@mapNotNull null
            val to = schedule.to ?: return@mapNotNull null
            TodayShuttleRoute(
                from = from,
                to = to,
                periodLabel = schedule.period.label,
                departures = schedule.rows.mapNotNull { row ->
                    row.services[weekday]?.let { service ->
                        TodayShuttleDeparture(row.departureTime, service.vehicle, service.count)
                    }
                },
            )
        }
        val departureCount = routes.sumOf { it.departures.size }
        val vehicleCount = routes.sumOf { route -> route.departures.sumOf { it.count } }
        val status = when {
            notice == null -> "未找到当前生效的班车时刻表"
            departureCount == 0 -> "今日暂无已安排班车"
            else -> "今日安排 $departureCount 个发车时刻 · $vehicleCount 辆车"
        }
        val currentTime = "%02d:%02d".format(
            Locale.ROOT,
            localNow.get(Calendar.HOUR_OF_DAY),
            localNow.get(Calendar.MINUTE),
        )
        val next = routes.flatMap { route ->
            route.departures.map { departure -> route to departure }
        }.filter { (_, departure) -> departure.time > currentTime }
            .minByOrNull { (_, departure) -> departure.time }
            ?.let { (route, departure) ->
                "下一班 ${departure.time} · ${route.from} → ${route.to}"
            }
        return TodayShuttlePresentation(
            status = status,
            nextDeparture = next ?: if (departureCount > 0) "今日班车已结束" else null,
            noticeTitle = notice?.title,
            noticeURL = notice?.sourceURL,
            stops = notice?.stops.orEmpty(),
            notes = notice?.notes.orEmpty(),
            routes = routes,
            isStale = snapshot.status == "stale",
        )
    }

    private fun selectCurrentNotice(
        notices: List<ShuttleBusNotice>,
        today: String,
    ): Pair<ShuttleBusNotice, List<ShuttleBusSchedule>>? {
        notices.filter { it.publishedAt <= today }.forEach { notice ->
            val parsed = notice.schedules.filter {
                it.parseStatus == "parsed" && it.rows.isNotEmpty()
            }
            if (parsed.isEmpty()) return@forEach
            val explicit = parsed.filter { schedule ->
                val period = schedule.period
                period.startDate != null && period.startDate <= today &&
                    (period.endDate == null || period.endDate >= today)
            }
            if (explicit.isNotEmpty()) {
                val latestStart = explicit.maxOf { it.period.startDate.orEmpty() }
                return notice to explicit.filter { it.period.startDate.orEmpty() == latestStart }
            }
            // The newest usable notice is authoritative. Unknown, upcoming or
            // ended periods are never presented as the currently effective
            // timetable, and an older notice is not resurrected in a gap.
            return null
        }
        return null
    }

    private fun weekdayKey(dayOfWeek: Int): String = when (dayOfWeek) {
        Calendar.MONDAY -> "monday"
        Calendar.TUESDAY -> "tuesday"
        Calendar.WEDNESDAY -> "wednesday"
        Calendar.THURSDAY -> "thursday"
        Calendar.FRIDAY -> "friday"
        Calendar.SATURDAY -> "saturday"
        else -> "sunday"
    }
}

internal class ShuttleBusClient(
    private val fetchPublicJson: (URI, String, String, Int) -> String =
        FixedPublicJsonTransport::fetch,
) {
    fun fetch(): ShuttleBusSnapshot = try {
        val payload = fetchPublicJson(
            URI.create(CalendarDailyInfoSources.shuttleBus),
            "https",
            "where-to-study.cn",
            CalendarDailyInfoSources.shuttlePayloadLimit,
        )
        ShuttleBusResponseParser.parse(payload)
    } catch (error: DailyInfoClientException) {
        throw DailyInfoClientException("班车信息获取失败：${error.message}", error)
    } catch (error: Exception) {
        throw DailyInfoClientException("班车信息获取失败。", error)
    }
}

internal class ShuttleBusRepository(
    private val client: ShuttleBusClient = ShuttleBusClient(),
    private val usesSampleData: Boolean = DailyCourseNotificationRuntimeMode.isUiTesting,
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val observers = CopyOnWriteArrayList<() -> Unit>()
    private val loading = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    @Volatile var snapshot: ShuttleBusSnapshot? = null
        private set
    @Volatile var error: String? = null
        private set
    @Volatile private var fetchedAtMillis: Long = Long.MIN_VALUE

    fun isLoading(): Boolean = loading.get()

    fun addObserver(observer: () -> Unit) {
        if (!closed.get()) observers.addIfAbsent(observer)
    }

    fun removeObserver(observer: () -> Unit) {
        observers.remove(observer)
    }

    fun load(force: Boolean = false) {
        val nowMillis = System.nanoTime() / 1_000_000L
        val hasFreshSnapshot = snapshot != null &&
            nowMillis - fetchedAtMillis in 0 until CACHE_MILLIS
        if (closed.get() || (!force && hasFreshSnapshot) ||
            !loading.compareAndSet(false, true)
        ) return
        error = null
        try {
            worker.execute {
                runCatching {
                    if (usesSampleData) sampleSnapshot() else client.fetch()
                }.onSuccess {
                    snapshot = it
                    fetchedAtMillis = System.nanoTime() / 1_000_000L
                }
                    .onFailure { error = it.message ?: "班车信息获取失败。" }
                loading.set(false)
                if (!closed.get()) handler.post {
                    if (!closed.get()) observers.toList().forEach { it() }
                }
            }
        } catch (_: RejectedExecutionException) {
            loading.set(false)
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        observers.clear()
        handler.removeCallbacksAndMessages(null)
        worker.shutdownNow()
    }

    private fun sampleSnapshot(): ShuttleBusSnapshot {
        val now = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = now.timeZone
        }.format(now.time)
        val services = mapOf(
            "monday" to ShuttleBusService("大巴", 1),
            "tuesday" to ShuttleBusService("大巴", 1),
            "wednesday" to ShuttleBusService("大巴", 1),
            "thursday" to ShuttleBusService("大巴", 1),
            "friday" to ShuttleBusService("大巴", 1),
            "saturday" to ShuttleBusService("大巴", 1),
            "sunday" to ShuttleBusService("大巴", 1),
        )
        return ShuttleBusSnapshot(
            generatedAt = "${today}T00:00:00+08:00",
            status = "healthy",
            sourceName = "北京邮电大学后勤部",
            sourcePage = "https://hq.bupt.edu.cn/tzgg.htm",
            notices = listOf(ShuttleBusNotice(
                id = "sample-shuttle",
                title = "示例两校区班车时刻表",
                publishedAt = today,
                sourceURL = "https://hq.bupt.edu.cn/tzgg.htm",
                kind = "regular_schedule",
                parseStatus = "parsed",
                stops = listOf("西土城路校区" to "教三楼西侧", "沙河校区" to "学生活动中心南侧"),
                notes = listOf("请提前五分钟候车。"),
                schedules = listOf(
                    ShuttleBusSchedule(
                        ShuttleBusPeriod("当前执行时段", today, null),
                        "西土城路校区", "沙河校区", "parsed",
                        listOf(ShuttleBusRow("08:30", services), ShuttleBusRow("13:30", services)),
                    ),
                    ShuttleBusSchedule(
                        ShuttleBusPeriod("当前执行时段", today, null),
                        "沙河校区", "西土城路校区", "parsed",
                        listOf(ShuttleBusRow("09:50", services), ShuttleBusRow("17:30", services)),
                    ),
                ),
            )),
        )
    }

    private companion object {
        const val CACHE_MILLIS = 5 * 60 * 1_000L
    }
}
