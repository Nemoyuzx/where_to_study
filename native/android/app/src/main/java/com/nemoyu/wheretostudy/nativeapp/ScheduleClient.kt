package com.nemoyu.wheretostudy.nativeapp

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

class ScheduleClientException(
    message: String,
    val retryable: Boolean = false,
) : Exception(message)

internal object SjdInputLimits {
    const val maxResponseBytes = 2 * 1024 * 1024
}

internal object SjdResponseReader {
    fun read(stream: InputStream?, declaredLength: Long): String {
        if (declaredLength > SjdInputLimits.maxResponseBytes) {
            throw ScheduleClientException("移动教务返回的数据超过大小限制。")
        }
        if (stream == null) return ""

        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        stream.use { input ->
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                total += count
                if (total > SjdInputLimits.maxResponseBytes) {
                    throw ScheduleClientException("移动教务返回的数据超过大小限制。")
                }
                output.write(buffer, 0, count)
            }
        }

        return String(output.toByteArray(), StandardCharsets.UTF_8)
    }
}

internal object SjdRedirectPolicy {
    const val maxRedirects = 5

    private val allowedOrigin = URI.create(SjdApiClient.ORIGIN)
    private val redirectStatuses = setOf(
        HttpURLConnection.HTTP_MOVED_PERM,
        HttpURLConnection.HTTP_MOVED_TEMP,
        HttpURLConnection.HTTP_SEE_OTHER,
        307,
        308,
    )

    fun isRedirect(status: Int): Boolean = status in redirectStatuses

    fun followUp(status: Int, method: String): SjdRedirectRequest {
        val normalizedMethod = method.uppercase(Locale.ROOT)
        return when {
            status == HttpURLConnection.HTTP_SEE_OTHER && normalizedMethod != "HEAD" ->
                SjdRedirectRequest("GET", preserveBody = false)
            status in setOf(
                HttpURLConnection.HTTP_MOVED_PERM,
                HttpURLConnection.HTTP_MOVED_TEMP,
            ) && normalizedMethod == "POST" ->
                SjdRedirectRequest("GET", preserveBody = false)
            else -> SjdRedirectRequest(normalizedMethod, preserveBody = true)
        }
    }

    fun resolve(current: URI, location: String?, redirectsFollowed: Int): URI {
        if (redirectsFollowed >= maxRedirects) {
            throw ScheduleClientException("移动教务重定向次数过多。")
        }
        val target = runCatching {
            current.resolve(location?.takeIf(String::isNotBlank) ?: error("missing location"))
        }.getOrElse {
            throw ScheduleClientException("移动教务返回了无效的重定向地址。")
        }
        if (!isAllowed(target)) {
            throw ScheduleClientException("移动教务拒绝了不安全的重定向。")
        }
        return target
    }

    fun isAllowed(target: URI): Boolean =
        target.scheme.equals("https", ignoreCase = true) &&
            target.host.equals(allowedOrigin.host, ignoreCase = true) &&
            target.userInfo == null &&
            hasAllowedPort(target)

    private fun hasAllowedPort(target: URI): Boolean = if (target.port == -1) {
        target.rawAuthority?.equals(target.host, ignoreCase = true) == true &&
            effectivePort(target) == effectivePort(allowedOrigin)
    } else {
        target.port == effectivePort(allowedOrigin)
    }

    private fun effectivePort(uri: URI): Int = if (uri.port == -1) 443 else uri.port
}

internal data class SjdRedirectRequest(
    val method: String,
    val preserveBody: Boolean,
)

class SjdApiClient {
    fun login(credentials: Credentials): String {
        val account = credentials.account.trim()
        if (account.isEmpty() || credentials.password.isEmpty()) {
            throw ScheduleClientException("请先在设置中填写并保存教务账号和密码。")
        }
        val login = post(
            path = "/bjyddx/login",
            referer = LOGIN_REFERER,
            form = mapOf("userNo" to account, "pwd" to credentials.password),
        )
        if (!isSuccessful(login)) {
            throw ScheduleClientException(message(login, "移动教务登录失败。"))
        }
        val token = login.optJSONObject("data")?.optString("token").orEmpty().trim()
        if (token.isEmpty()) {
            throw ScheduleClientException("移动教务登录成功但没有返回 token。")
        }
        return token
    }

    fun post(
        path: String,
        referer: String,
        form: Map<String, String> = emptyMap(),
        token: String? = null,
    ): JSONObject = request("POST", path, referer, form, token)

    fun get(
        path: String,
        referer: String,
        query: Map<String, String> = emptyMap(),
        token: String? = null,
    ): JSONObject {
        val queryString = if (query.isEmpty()) "" else "?${String(formData(query), StandardCharsets.UTF_8)}"
        return request("GET", "$path$queryString", referer, emptyMap(), token)
    }

    fun isSuccessful(payload: JSONObject): Boolean = payload.opt("code").stringValue() == "1"

    fun message(payload: JSONObject, fallback: String): String =
        payload.opt("Msg").stringValue().ifEmpty { payload.opt("msg").stringValue() }.ifEmpty { fallback }

    private fun request(
        method: String,
        path: String,
        referer: String,
        form: Map<String, String>,
        token: String?,
    ): JSONObject {
        var target = URI.create("$ORIGIN$path")
        var requestMethod = method
        var requestForm = form
        var redirectsFollowed = 0
        while (true) {
            val connection = target.toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = requestMethod
                connection.connectTimeout = 20_000
                connection.readTimeout = 30_000
                connection.instanceFollowRedirects = false
                connection.doInput = true
                connection.setRequestProperty("Origin", ORIGIN)
                connection.setRequestProperty("Referer", referer)
                connection.setRequestProperty("User-Agent", "Mozilla/5.0")
                token?.let { connection.setRequestProperty("token", it) }
                if (requestForm.isNotEmpty() && requestMethod != "GET" && requestMethod != "HEAD") {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    connection.outputStream.use { stream -> stream.write(formData(requestForm)) }
                }
                val status = connection.responseCode
                if (SjdRedirectPolicy.isRedirect(status)) {
                    target = SjdRedirectPolicy.resolve(
                        current = target,
                        location = connection.getHeaderField("Location"),
                        redirectsFollowed = redirectsFollowed,
                    )
                    val followUp = SjdRedirectPolicy.followUp(status, requestMethod)
                    requestMethod = followUp.method
                    if (!followUp.preserveBody) requestForm = emptyMap()
                    redirectsFollowed += 1
                    continue
                }
                val stream = if (status in 200..399) connection.inputStream else connection.errorStream
                val body = SjdResponseReader.read(stream, connection.contentLengthLong)
                if (status !in 200..399) {
                    throw ScheduleClientException(
                        "移动教务请求失败，HTTP $status。",
                        retryable = status == HTTP_REQUEST_TIMEOUT ||
                            status == HTTP_TOO_MANY_REQUESTS ||
                            status >= HTTP_SERVER_ERROR,
                    )
                }
                return runCatching { JSONObject(body) }.getOrElse {
                    throw ScheduleClientException("移动教务返回了无法识别的数据。")
                }
            } finally {
                connection.disconnect()
            }
        }
    }

    private fun formData(values: Map<String, String>): ByteArray = values.entries
        .sortedBy(Map.Entry<String, String>::key)
        .joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }
        .toByteArray(StandardCharsets.UTF_8)

    private fun encode(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8.name())

    companion object {
        private const val HTTP_REQUEST_TIMEOUT = 408
        private const val HTTP_TOO_MANY_REQUESTS = 429
        private const val HTTP_SERVER_ERROR = 500
        const val ORIGIN = "https://jwglweixin.bupt.edu.cn"
        const val LOGIN_REFERER = "$ORIGIN/sjd/#/login"
        const val CLASSROOM_REFERER = "$ORIGIN/sjd/#/restClassroom"
    }
}

class SjdScheduleClient(
    private val api: SjdApiClient = SjdApiClient(),
) {
    fun fetch(
        credentials: Credentials,
        fallbackTermID: String,
        fallbackTermStartDate: String,
    ): ScheduleSnapshot {
        val token = api.login(credentials)
        val current = post(
            path = "/bjyddx/student/curriculum?week=",
            referer = SjdApiClient.CLASSROOM_REFERER,
            token = token,
        )
        val curriculum = post(
            path = "/bjyddx/student/curriculum?week=all",
            referer = SjdApiClient.CLASSROOM_REFERER,
            token = token,
        )
        if (!api.isSuccessful(current) || !api.isSuccessful(curriculum)) {
            throw ScheduleClientException("移动教务课表获取失败。")
        }
        return SjdScheduleParser.parse(
            current = current,
            curriculum = curriculum,
            fallbackTermID = fallbackTermID,
            fallbackTermStartDate = fallbackTermStartDate,
        )
    }

    private fun post(
        path: String,
        referer: String,
        token: String? = null,
    ): JSONObject = api.post(path, referer, token = token)
}

object SjdScheduleParser {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun parse(
        current: JSONObject,
        curriculum: JSONObject,
        fallbackTermID: String,
        fallbackTermStartDate: String,
        fetchedAt: String = timestamp(Date()),
    ): ScheduleSnapshot {
        val currentRoot = current.optJSONArray("data")?.optJSONObject(0)
            ?: throw ScheduleClientException("移动教务课表返回为空。")
        val curriculumRoot = curriculum.optJSONArray("data")?.optJSONObject(0)
            ?: throw ScheduleClientException("移动教务课表返回为空。")
        val termID = currentRoot.opt("semesterId").stringValue()
            .ifEmpty { currentRoot.opt("xnxq01id").stringValue() }
            .ifEmpty { fallbackTermID }
        val termStartDate = inferTermStartDate(currentRoot) ?: fallbackTermStartDate
        val rawCourses = mutableListOf<JSONObject>()
        collectCourses(curriculumRoot.opt("item") ?: curriculumRoot.opt("courses"), rawCourses)
        val seen = mutableSetOf<String>()
        var courses = rawCourses.mapNotNull(::parseCourse).filter { seen.add(it.id) }
        courses = ScheduleLogic.applyingExamWeeks(courses)
            .sortedWith(compareBy(Course::weekday, Course::startSlot, Course::name))
        return ScheduleSnapshot(termID, termStartDate, fetchedAt, courses)
    }

    private fun collectCourses(value: Any?, output: MutableList<JSONObject>) {
        when (value) {
            is JSONObject -> {
                if (value.has("courseName") || value.has("jx0408id")) {
                    output += value
                } else {
                    value.keys().forEach { key -> collectCourses(value.opt(key), output) }
                }
            }
            is JSONArray -> (0 until value.length()).forEach { collectCourses(value.opt(it), output) }
        }
    }

    private fun parseCourse(raw: JSONObject): Course? {
        val (startSlot, endSlot) = slots(raw) ?: return null
        val weekday = raw.opt("weekDay").stringValue()
            .ifEmpty { raw.opt("classTime").stringValue() }
            .firstOrNull()?.digitToIntOrNull() ?: return null
        if (weekday !in 1..7) return null
        val name = raw.opt("courseName").stringValue().trim().ifEmpty { "未命名课程" }
        val teacher = raw.opt("teacherName").stringValue().trim()
        val building = raw.opt("buildingName").stringValue().trim()
        val rawRoom = raw.opt("classroomName").stringValue().trim()
            .ifEmpty { raw.opt("location").stringValue().trim() }
        val room = normalizeCourseRoom(rawRoom)
        val location = when {
            building.isNotEmpty() && room.isNotEmpty() && !room.contains(building) -> "$building-$room"
            room.isNotEmpty() -> room
            else -> building
        }
        val weekText = raw.opt("classWeek").stringValue().trim()
            .ifEmpty { raw.opt("classWeekDetails").stringValue().trim() }
        val weeks = weekNumbers(raw)
        val stable = listOf(
            raw.opt("jx0408id").stringValue(), name, teacher, location, weekText,
            weekday.toString(), startSlot.toString(), endSlot.toString(),
        ).joinToString("|")
        val id = MessageDigest.getInstance("SHA-1")
            .digest(stable.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
            .take(12)
        val startTime = raw.opt("startTime").stringValue().ifEmpty { AppMetadata.slots[startSlot].start }
        val endTime = raw.opt("endTIme").stringValue()
            .ifEmpty { raw.opt("endTime").stringValue() }
            .ifEmpty { AppMetadata.slots[endSlot].end }
        return Course(
            id = id,
            name = name,
            teacher = teacher,
            room = location,
            weekText = weekText,
            weekNumbers = weeks,
            examWeekNumbers = emptyList(),
            weekday = weekday,
            startSlot = startSlot,
            endSlot = endSlot,
            sectionText = "${startSlot + 1}-${endSlot + 1}节",
            timeRange = "$startTime-$endTime",
        )
    }

    internal fun normalizeCourseRoom(value: String): String {
        val normalized = value.trim()
            .replace('－', '-')
            .replace('—', '-')
            .replace('–', '-')
        val parts = normalized.split('-')
        if (parts.size != 2) return normalized
        val buildingPrefix = parts[0].removePrefix("教")
        return if (
            buildingPrefix.length == 1 && buildingPrefix.all(Char::isDigit) &&
            parts[1].length == 3 && parts[1].all(Char::isDigit)
        ) {
            parts[1]
        } else {
            normalized
        }
    }

    private fun weekNumbers(raw: JSONObject): List<Int> {
        val details = raw.opt("classWeekDetails").stringValue()
        val explicit = integers(details)
        if (explicit.isNotEmpty()) return explicit.distinct().sorted()
        val text = raw.opt("classWeek").stringValue()
            .replace("周", "").replace(" ", "").replace("，", ",")
        val odd = text.contains("单")
        val even = text.contains("双")
        val weeks = text.split(',').flatMap { item ->
            val numbers = integers(item)
            if (numbers.size >= 2) (numbers[0]..numbers[1]).toList() else numbers
        }
        return weeks.distinct().filter { (!odd || it % 2 == 1) && (!even || it % 2 == 0) }.sorted()
    }

    private fun slots(raw: JSONObject): Pair<Int, Int>? {
        val classTime = raw.opt("classTime").stringValue().drop(1)
        var nodes = Regex("\\d{2}").findAll(classTime).mapNotNull { it.value.toIntOrNull() }.toList()
        if (nodes.isEmpty()) nodes = integers(raw.opt("weekNoteDetail").stringValue())
        val minimum = nodes.minOrNull() ?: return null
        val maximum = nodes.maxOrNull() ?: return null
        if (minimum < 1 || maximum > AppMetadata.slots.size || minimum > maximum) return null
        return minimum - 1 to maximum - 1
    }

    private fun inferTermStartDate(root: JSONObject): String? {
        val week = root.opt("week").stringValue().toIntOrNull()
            ?: root.optJSONArray("topInfo")?.optJSONObject(0)?.opt("week").stringValue().toIntOrNull()
            ?: return null
        if (week < 1) return null
        val dates = root.optJSONArray("date") ?: return null
        val dated = (0 until dates.length()).mapNotNull(dates::optJSONObject)
            .firstOrNull { it.has("mxrq") && it.opt("zc").stringValue() != "all" }
            ?: return null
        val day = parseDate(dated.opt("mxrq").stringValue()) ?: return null
        val weekday = dated.opt("xqid").stringValue().toIntOrNull()
            ?: ((day.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        day.add(Calendar.DAY_OF_MONTH, -(weekday - 1) - ((week - 1) * 7))
        return contractDate().format(day.time)
    }

    private fun parseDate(value: String): Calendar? = runCatching {
        Calendar.getInstance(shanghai).apply { time = contractDate().parse(value) ?: error("invalid date") }
    }.getOrNull()

    private fun integers(value: String): List<Int> = Regex("\\d+")
        .findAll(value).mapNotNull { it.value.toIntOrNull() }.toList()

    private fun contractDate(): SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = shanghai
        isLenient = false
    }

    private fun timestamp(date: Date): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
        timeZone = shanghai
    }.format(date)
}

private fun Any?.stringValue(): String = when (this) {
    null, JSONObject.NULL -> ""
    is String -> this
    is Number -> toString()
    else -> toString()
}
