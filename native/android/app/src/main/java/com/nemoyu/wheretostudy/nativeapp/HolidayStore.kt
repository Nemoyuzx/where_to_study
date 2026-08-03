package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

object HolidaysJsonCodec {
    fun decode(value: String): HolidaysSnapshot {
        return try {
            val root = JSONObject(value)
            root.requireKeys(SNAPSHOT_KEYS, "本地节假日缓存字段不正确。")
            val items = root.optJSONArray("items")
                ?: throw HolidayClientException("本地节假日缓存的 items 格式不正确。")
            val snapshot = HolidaysSnapshot(
                year = root.strictInt("year"),
                source = root.strictString("source"),
                fetchedAt = root.strictString("fetched_at"),
                items = (0 until items.length()).map { index ->
                    val item = items.optJSONObject(index)
                        ?: throw HolidayClientException("本地节假日缓存的条目格式不正确。")
                    item.requireKeys(ITEM_KEYS, "本地节假日缓存的条目字段不正确。")
                    HolidayItem(
                        date = item.strictString("date"),
                        name = item.strictString("name"),
                        type = item.strictString("type"),
                    )
                },
            )
            HolidaySnapshotValidator.validate(snapshot)
            snapshot
        } catch (error: HolidayClientException) {
            throw error
        } catch (error: Exception) {
            throw HolidayClientException("本地节假日缓存格式不正确。", error)
        }
    }

    fun encode(snapshot: HolidaysSnapshot): String {
        HolidaySnapshotValidator.validate(snapshot)
        return JSONObject()
            .put("year", snapshot.year)
            .put("source", snapshot.source)
            .put("fetched_at", snapshot.fetchedAt)
            .put("items", JSONArray().apply {
                snapshot.items.forEach { item ->
                    put(JSONObject()
                        .put("date", item.date)
                        .put("name", item.name)
                        .put("type", item.type))
                }
            })
            .toString(2)
    }

    private fun JSONObject.requireKeys(expected: Set<String>, message: String) {
        val actual = buildSet {
            val iterator = keys()
            while (iterator.hasNext()) add(iterator.next())
        }
        if (actual != expected) throw HolidayClientException(message)
    }

    private fun JSONObject.strictString(name: String): String =
        opt(name) as? String
            ?: throw HolidayClientException("本地节假日缓存的 $name 格式不正确。")

    private fun JSONObject.strictInt(name: String): Int {
        val number = opt(name) as? Number
            ?: throw HolidayClientException("本地节假日缓存的 $name 格式不正确。")
        val longValue = number.toLong()
        if (number.toDouble() != longValue.toDouble() || longValue !in Int.MIN_VALUE..Int.MAX_VALUE) {
            throw HolidayClientException("本地节假日缓存的 $name 格式不正确。")
        }
        return longValue.toInt()
    }

    private val SNAPSHOT_KEYS = setOf("year", "source", "fetched_at", "items")
    private val ITEM_KEYS = setOf("date", "name", "type")
}

internal object HolidaySnapshotValidator {
    fun validate(snapshot: HolidaysSnapshot, expectedYear: Int? = null) {
        if (snapshot.year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) {
            throw HolidayClientException("本地节假日缓存的年份不在支持范围内。")
        }
        if (expectedYear != null && snapshot.year != expectedYear) {
            throw HolidayClientException("本地节假日缓存年份与请求不一致。")
        }
        if (snapshot.source.isBlank() || snapshot.source.codePointLength() > HolidayInputLimits.maxSourceLength) {
            throw HolidayClientException("本地节假日缓存的数据源不正确。")
        }
        if (!isContractTimestamp(snapshot.fetchedAt)) {
            throw HolidayClientException("本地节假日缓存的获取时间不正确。")
        }
        if (snapshot.items.size > HolidayInputLimits.maxExpandedItems) {
            throw HolidayClientException("本地节假日缓存的条目数量超过限制。")
        }
        snapshot.items.forEach { item ->
            val date = parseContractDate(item.date)
                ?: throw HolidayClientException("本地节假日缓存的日期不正确。")
            if (date.substring(0, 4).toInt() != snapshot.year) {
                throw HolidayClientException("本地节假日缓存包含其他年份的日期。")
            }
            if (item.name.isBlank() || item.name.codePointLength() > HolidayInputLimits.maxNameLength) {
                throw HolidayClientException("本地节假日缓存的名称不正确。")
            }
            if (item.type != "holiday" && item.type != "workday") {
                throw HolidayClientException("本地节假日缓存的类型不正确。")
            }
        }
    }

    private fun parseContractDate(value: String): String? {
        if (!CONTRACT_DATE_PATTERN.matches(value)) return null
        val position = ParsePosition(0)
        val parsed = contractDate().parse(value, position) ?: return null
        return value.takeIf {
            position.index == value.length && contractDate().format(parsed) == value
        }
    }

    private fun isContractTimestamp(value: String): Boolean {
        if (value.length > HolidayInputLimits.maxTimestampLength || !TIMESTAMP_PATTERN.matches(value)) {
            return false
        }
        val position = ParsePosition(0)
        return timestampFormat().parse(value, position) != null && position.index == value.length
    }

    private fun contractDate(): SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = SHANGHAI
        isLenient = false
    }

    private fun timestampFormat(): SimpleDateFormat =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
            timeZone = SHANGHAI
            isLenient = false
        }

    private val SHANGHAI = TimeZone.getTimeZone("Asia/Shanghai")
    private val CONTRACT_DATE_PATTERN = Regex("\\d{4}-\\d{2}-\\d{2}")
    private val TIMESTAMP_PATTERN =
        Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:Z|[+-]\\d{2}:\\d{2})")
}

private fun String.codePointLength(): Int = codePointCount(0, length)

private interface HolidayCacheIO {
    fun exists(file: File): Boolean
    fun length(file: File): Long
    fun openRead(file: File): InputStream
    fun write(file: File, bytes: ByteArray)
}

private object AtomicHolidayCacheIO : HolidayCacheIO {
    override fun exists(file: File): Boolean = AtomicFile(file).baseFile.exists()

    override fun length(file: File): Long = AtomicFile(file).baseFile.length()

    override fun openRead(file: File): InputStream = AtomicFile(file).openRead()

    override fun write(file: File, bytes: ByteArray) {
        val atomicFile = AtomicFile(file)
        val output = atomicFile.startWrite()
        try {
            output.write(bytes)
            output.flush()
            atomicFile.finishWrite(output)
        } catch (error: Exception) {
            atomicFile.failWrite(output)
            throw error
        }
    }
}

private object PlainHolidayCacheIO : HolidayCacheIO {
    override fun exists(file: File): Boolean = file.exists()

    override fun length(file: File): Long = file.length()

    override fun openRead(file: File): InputStream = file.inputStream()

    override fun write(file: File, bytes: ByteArray) = file.writeBytes(bytes)
}

class HolidayStore private constructor(
    private val directory: File,
    private val cacheIO: HolidayCacheIO,
) {
    constructor(context: Context) : this(
        directory = File(context.filesDir, DIRECTORY_NAME),
        cacheIO = AtomicHolidayCacheIO,
    )

    internal constructor(directory: File) : this(
        directory = directory,
        cacheIO = PlainHolidayCacheIO,
    )

    fun load(year: Int): HolidaysSnapshot? {
        if (year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) {
            throw HolidayClientException("节假日年份不在支持范围内。")
        }
        val target = file(year)
        if (!cacheIO.exists(target)) return null
        if (cacheIO.length(target) > HolidayInputLimits.maxResponseBytes) {
            throw HolidayClientException("本地节假日缓存过大。")
        }
        val bytes = readBounded(cacheIO.openRead(target))
        if (bytes.isEmpty()) return null
        val content = decodeUtf8(bytes)
        if (content.isBlank()) return null
        return HolidaysJsonCodec.decode(content).also {
            HolidaySnapshotValidator.validate(it, expectedYear = year)
        }
    }

    fun save(snapshot: HolidaysSnapshot) {
        HolidaySnapshotValidator.validate(snapshot)
        val bytes = HolidaysJsonCodec.encode(snapshot).toByteArray(StandardCharsets.UTF_8)
        if (bytes.size > HolidayInputLimits.maxResponseBytes) {
            throw HolidayClientException("本地节假日缓存过大。")
        }
        if (!directory.exists() && !directory.mkdirs()) {
            throw HolidayClientException("无法创建本地节假日目录。")
        }
        cacheIO.write(file(snapshot.year), bytes)
    }

    fun clear() {
        if (directory.exists() && !directory.deleteRecursively()) {
            throw HolidayClientException("无法清除本地节假日缓存。")
        }
    }

    private fun readBounded(stream: InputStream): ByteArray {
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
                    throw HolidayClientException("本地节假日缓存过大。")
                }
                output.write(buffer, 0, count)
            }
        }
        return output.toByteArray()
    }

    private fun decodeUtf8(bytes: ByteArray): String {
        return try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (error: Exception) {
            throw HolidayClientException("本地节假日缓存编码不正确。", error)
        }
    }

    private fun file(year: Int): File = File(directory, "holidays_$year.json")

    private companion object {
        const val DIRECTORY_NAME = "holidays"
    }
}
