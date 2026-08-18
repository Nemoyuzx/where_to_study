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
import org.json.JSONObject

class HolidayClientException(message: String, cause: Throwable? = null) : Exception(message, cause)

internal object HolidayInputLimits {
    const val maxResponseBytes = 256 * 1024
    const val maxRecords = 128
    const val maxNameLength = 80
    const val maxSourceLength = 512
    const val maxTimestampLength = 64
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
                // Fail closed on redirects: the source is a pinned unpkg.com
                // URL, so a redirect to another host must not be followed.
                connection.instanceFollowRedirects = false
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
                val payload = runCatching { JSONObject(body) }.getOrElse {
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
        payload: JSONObject,
        year: Int,
        source: String,
        fetchedAt: String,
    ): HolidaysSnapshot {
        if (year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) {
            throw HolidayClientException("节假日年份不在支持范围内。")
        }
        val payloadYear = payload.opt("year") as? Int
            ?: throw HolidayClientException("节假日服务返回的年份格式不正确。")
        if (payloadYear != year) {
            throw HolidayClientException("节假日数据年份与请求不一致。")
        }
        val region = payload.opt("region") as? String
            ?: throw HolidayClientException("节假日服务返回的区域格式不正确。")
        if (region != "CN") {
            throw HolidayClientException("节假日数据区域不正确。")
        }
        val dates = payload.opt("dates") as? JSONArray
            ?: throw HolidayClientException("节假日服务返回的日期列表格式不正确。")
        if (dates.length() > HolidayInputLimits.maxRecords) {
            throw HolidayClientException("节假日服务返回的记录数量超过限制。")
        }

        val items = mutableListOf<HolidayItem>()
        val formatter = contractDate()
        for (index in 0 until dates.length()) {
            val raw = dates.optJSONObject(index)
                ?: throw HolidayClientException("节假日服务返回的记录格式不正确。")
            val rawChineseName = when {
                !raw.has("name_cn") -> null
                raw.opt("name_cn") is String -> raw.optString("name_cn").trim()
                else -> throw HolidayClientException("节假日服务返回的名称格式不正确。")
            }
            val rawFallbackName = when {
                !raw.has("name") -> null
                raw.opt("name") is String -> raw.optString("name").trim()
                else -> throw HolidayClientException("节假日服务返回的名称格式不正确。")
            }
            val name = rawChineseName?.takeIf(String::isNotEmpty) ?: rawFallbackName.orEmpty()
            if (name.isEmpty()) {
                throw HolidayClientException("节假日服务返回的名称不能为空。")
            }
            if (name.codePointCount(0, name.length) > HolidayInputLimits.maxNameLength) {
                throw HolidayClientException("节假日服务返回的名称超过长度限制。")
            }
            val rawType = raw.opt("type") as? String
                ?: throw HolidayClientException("节假日服务返回的类型格式不正确。")
            val rawDate = raw.opt("date") as? String
                ?: throw HolidayClientException("节假日服务返回的日期格式不正确。")
            val date = parseDate(rawDate)
                ?: throw HolidayClientException("节假日服务返回的日期格式不正确。")
            if (date.get(Calendar.YEAR) != year) {
                throw HolidayClientException("节假日数据包含其他年份的日期。")
            }
            val type = normalizeType(rawType)
            if (type != null) {
                if (items.size >= HolidayInputLimits.maxExpandedItems) {
                    throw HolidayClientException("节假日服务返回的展开记录数量超过限制。")
                }
                items += HolidayItem(
                    date = formatter.format(date.time),
                    name = name,
                    type = type,
                )
            }
        }
        if (items.isEmpty()) {
            throw HolidayClientException("节假日服务未返回可识别的法定节假日记录。")
        }
        return HolidaysSnapshot(
            year = year,
            source = source,
            fetchedAt = fetchedAt,
            items = items.sortedWith(compareBy(HolidayItem::date, HolidayItem::type, HolidayItem::name)),
        )
    }

    private fun normalizeType(value: String): String? = when (value) {
        "public_holiday" -> "holiday"
        "transfer_workday" -> "workday"
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
