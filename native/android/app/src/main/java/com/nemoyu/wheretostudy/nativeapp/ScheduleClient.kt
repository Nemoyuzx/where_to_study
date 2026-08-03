package com.nemoyu.wheretostudy.nativeapp

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

class ScheduleClientException(message: String) : Exception(message)

class SjdScheduleClient {
    fun fetch(
        credentials: Credentials,
        fallbackTermID: String,
        fallbackTermStartDate: String,
    ): ScheduleSnapshot {
        val account = credentials.account.trim()
        if (account.isEmpty() || credentials.password.isEmpty()) {
            throw ScheduleClientException("请先在设置中填写并保存教务账号和密码。")
        }
        val login = post(
            path = "/bjyddx/login",
            referer = "$ORIGIN/sjd/#/login",
            form = mapOf("userNo" to account, "pwd" to credentials.password),
        )
        if (!isSuccessful(login)) {
            throw ScheduleClientException(message(login, "移动教务登录失败。"))
        }
        val token = login.optJSONObject("data")?.optString("token").orEmpty().trim()
        if (token.isEmpty()) {
            throw ScheduleClientException("移动教务登录成功但没有返回 token。")
        }
        val current = post(
            path = "/bjyddx/student/curriculum?week=",
            referer = "$ORIGIN/sjd/#/restClassroom",
            token = token,
        )
        val curriculum = post(
            path = "/bjyddx/student/curriculum?week=all",
            referer = "$ORIGIN/sjd/#/restClassroom",
            token = token,
        )
        if (!isSuccessful(current) || !isSuccessful(curriculum)) {
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
        form: Map<String, String> = emptyMap(),
        token: String? = null,
    ): JSONObject {
        val connection = URI.create("$ORIGIN$path").toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 20_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.doInput = true
            connection.setRequestProperty("Origin", ORIGIN)
            connection.setRequestProperty("Referer", referer)
            connection.setRequestProperty("User-Agent", "Mozilla/5.0")
            token?.let { connection.setRequestProperty("token", it) }
            if (form.isNotEmpty()) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                connection.outputStream.use { stream -> stream.write(formData(form)) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..399) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (status !in 200..399) {
                throw ScheduleClientException("移动教务请求失败，HTTP $status。")
            }
            return runCatching { JSONObject(body) }.getOrElse {
                throw ScheduleClientException("移动教务返回了无法识别的数据。")
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun formData(values: Map<String, String>): ByteArray = values.entries
        .sortedBy(Map.Entry<String, String>::key)
        .joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }
        .toByteArray(StandardCharsets.UTF_8)

    private fun encode(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8.name())

    private fun isSuccessful(payload: JSONObject): Boolean = payload.opt("code").stringValue() == "1"

    private fun message(payload: JSONObject, fallback: String): String =
        payload.opt("Msg").stringValue().ifEmpty { payload.opt("msg").stringValue() }.ifEmpty { fallback }

    private companion object {
        const val ORIGIN = "http://jwglweixin.bupt.edu.cn"
    }
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
        val room = raw.opt("classroomName").stringValue().trim()
            .ifEmpty { raw.opt("location").stringValue().trim() }
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
