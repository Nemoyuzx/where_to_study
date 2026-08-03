package com.nemoyu.wheretostudy.nativeapp

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray

class HolidayClientException(message: String, cause: Throwable? = null) : Exception(message, cause)

internal object HolidayInputLimits {
    const val maxResponseBytes = 256 * 1024
    const val maxRecords = 128
    const val maxNameLength = 80
    const val maxSourceLength = 512
    const val maxTimestampLength = 64
    const val maxRangeEntries = 32
    const val maxRangeSpanDays = 32
    const val maxExpandedItems = 512
}

internal object HolidayUserAgent {
    val value: String
        get() = "WhereToStudyNative/${BuildConfig.VERSION_NAME}"
}

internal object HolidayResponseReader {
    fun read(stream: InputStream?, declaredLength: Long): String {
        if (declaredLength > HolidayInputLimits.maxResponseBytes) {
            throw HolidayClientException("节假日服务返回的数据超过大小限制。")
        }
        if (stream == null) {
            throw HolidayClientException("节假日服务未返回数据。")
        }

        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        stream.use { input ->
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                total += count
                if (total > HolidayInputLimits.maxResponseBytes) {
                    throw HolidayClientException("节假日服务返回的数据超过大小限制。")
                }
                output.write(buffer, 0, count)
            }
        }

        return try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(output.toByteArray()))
                .toString()
        } catch (error: Exception) {
            throw HolidayClientException("节假日服务返回的数据编码不正确。", error)
        }
    }
}

class HolidayClient(
    private val source: String = HolidayMetadata.source,
) {
    fun fetch(year: Int): HolidaysSnapshot {
        if (year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) {
            throw HolidayClientException("节假日年份不在支持范围内。")
        }
        return try {
            val connection = URI.create("$source/$year.json").toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"
                connection.connectTimeout = 15_000
                connection.readTimeout = 20_000
                connection.instanceFollowRedirects = true
                connection.doInput = true
                connection.setRequestProperty("Accept", "application/json")
                connection.setRequestProperty("User-Agent", HolidayUserAgent.value)
                val status = connection.responseCode
                if (status !in 200..299) {
                    throw HolidayClientException("节假日服务暂时不可用，HTTP $status。")
                }
                val body = HolidayResponseReader.read(
                    stream = connection.inputStream,
                    declaredLength = connection.contentLengthLong,
                )
                val payload = runCatching { JSONArray(body) }.getOrElse {
                    throw HolidayClientException("节假日服务返回的数据格式不正确。", it)
                }
                HolidaySourceParser.parse(
                    payload = payload,
                    year = year,
                    source = source,
                    fetchedAt = timestamp(),
                )
            } finally {
                connection.disconnect()
            }
        } catch (error: HolidayClientException) {
            throw error
        } catch (error: Exception) {
            throw HolidayClientException("无法获取节假日数据，请稍后重试。", error)
        }
    }

    private fun timestamp(date: Date = Date()): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
            timeZone = SHANGHAI
        }.format(date)

    private companion object {
        val SHANGHAI: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
    }
}

object HolidaySourceParser {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun parse(
        payload: JSONArray,
        year: Int,
        source: String,
        fetchedAt: String,
    ): HolidaysSnapshot {
        if (year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) {
            throw HolidayClientException("节假日年份不在支持范围内。")
        }
        if (payload.length() > HolidayInputLimits.maxRecords) {
            throw HolidayClientException("节假日服务返回的记录数量超过限制。")
        }

        val items = mutableListOf<HolidayItem>()
        val formatter = contractDate()
        for (index in 0 until payload.length()) {
            val raw = payload.optJSONObject(index)
                ?: throw HolidayClientException("节假日服务返回的记录格式不正确。")
            val rawName = raw.opt("name") as? String
                ?: throw HolidayClientException("节假日服务返回的名称格式不正确。")
            val name = rawName.trim()
            if (name.isEmpty()) {
                throw HolidayClientException("节假日服务返回的名称不能为空。")
            }
            if (name.codePointCount(0, name.length) > HolidayInputLimits.maxNameLength) {
                throw HolidayClientException("节假日服务返回的名称超过长度限制。")
            }
            val rawType = raw.opt("type") as? String
                ?: throw HolidayClientException("节假日服务返回的类型格式不正确。")
            val range = raw.opt("range") as? JSONArray
                ?: throw HolidayClientException("节假日服务返回的日期范围格式不正确。")
            if (range.length() == 0) {
                throw HolidayClientException("节假日服务返回的日期范围不能为空。")
            }
            if (range.length() > HolidayInputLimits.maxRangeEntries) {
                throw HolidayClientException("节假日服务返回的日期范围数量超过限制。")
            }
            val rangeDates = (0 until range.length()).map { rangeIndex ->
                val rawDate = range.opt(rangeIndex) as? String
                    ?: throw HolidayClientException("节假日服务返回的日期格式不正确。")
                parseDate(rawDate)
                    ?: throw HolidayClientException("节假日服务返回的日期格式不正确。")
            }
            rangeDates.zipWithNext().forEach { (previous, next) ->
                if (!next.after(previous)) {
                    throw HolidayClientException("节假日服务返回的日期范围顺序不正确。")
                }
            }
            val type = normalizeType(rawType)
            val start = rangeDates.first()
            val end = rangeDates.last()
            val current = start.clone() as Calendar
            var spanDays = 0
            while (!current.after(end)) {
                spanDays += 1
                if (spanDays > HolidayInputLimits.maxRangeSpanDays) {
                    throw HolidayClientException("节假日服务返回的单条日期跨度超过限制。")
                }
                if (type != null && current.get(Calendar.YEAR) == year) {
                    if (items.size >= HolidayInputLimits.maxExpandedItems) {
                        throw HolidayClientException("节假日服务返回的展开记录数量超过限制。")
                    }
                    items += HolidayItem(
                        date = formatter.format(current.time),
                        name = name,
                        type = type,
                    )
                }
                current.add(Calendar.DAY_OF_MONTH, 1)
            }
        }
        return HolidaysSnapshot(
            year = year,
            source = source,
            fetchedAt = fetchedAt,
            items = items.sortedWith(compareBy(HolidayItem::date, HolidayItem::type, HolidayItem::name)),
        )
    }

    private fun normalizeType(value: String): String? = when (value) {
        "holiday" -> "holiday"
        "workingday", "workday" -> "workday"
        else -> null
    }

    private fun parseDate(value: String): Calendar? {
        if (!CONTRACT_DATE_PATTERN.matches(value)) return null
        return runCatching {
            Calendar.getInstance(shanghai).apply {
                isLenient = false
                time = contractDate().parse(value) ?: error("invalid date")
            }
        }.getOrNull()
    }

    private fun contractDate(): SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = shanghai
        isLenient = false
    }

    private val CONTRACT_DATE_PATTERN = Regex("\\d{4}-\\d{2}-\\d{2}")
}
