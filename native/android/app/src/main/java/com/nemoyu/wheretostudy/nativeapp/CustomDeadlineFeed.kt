package com.nemoyu.wheretostudy.nativeapp

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.URI
import java.nio.charset.StandardCharsets
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

data class CustomDeadlineFeedMetadata(
    val sourceName: String,
    val homepage: String?,
    val itemCount: Int,
)

data class ParsedCustomDeadlineFeed(
    val sourceURL: String,
    val sourceName: String,
    val homepage: String?,
    val updatedAt: String?,
    val itemsByDate: Map<String, List<PublicDeadlineItem>>,
) {
    val metadata: CustomDeadlineFeedMetadata
        get() = CustomDeadlineFeedMetadata(
            sourceName = sourceName,
            homepage = homepage,
            itemCount = itemsByDate.values.sumOf(List<PublicDeadlineItem>::size),
        )
}

internal object CustomDeadlineFeedURLValidator {
    fun validatedURI(rawValue: String): URI {
        val normalized = rawValue.trim()
        val uri = runCatching { URI.create(normalized) }.getOrElse {
            throw DailyInfoClientException("自定义日程地址格式不正确。", it)
        }
        validate(uri)
        return uri
    }

    fun validate(uri: URI) {
        if (!uri.scheme.equals("https", ignoreCase = true) ||
            uri.host.isNullOrBlank() || uri.userInfo != null || uri.fragment != null ||
            uri.port == 0 || uri.port < -1 || uri.port > 65_535
        ) {
            throw DailyInfoClientException("自定义日程地址必须是无凭据的 HTTPS URL。")
        }
        val host = uri.host
            .trim('[', ']')
            .trimEnd('.')
            .lowercase(Locale.ROOT)
        if (host == "localhost" || host.endsWith(".localhost")) {
            throw DailyInfoClientException("自定义日程地址不能指向本机。")
        }
        if (isForbiddenIPAddressLiteral(host)) {
            throw DailyInfoClientException("自定义日程地址不能使用私有或保留 IP。")
        }
    }

    internal fun isForbiddenIPAddressLiteral(host: String): Boolean {
        val looksLikeIPv4 = Regex("^[0-9.]+$").matches(host) ||
            Regex("^0x[0-9a-f]+$", RegexOption.IGNORE_CASE).matches(host)
        val looksLikeIPv6 = ':' in host
        if (!looksLikeIPv4 && !looksLikeIPv6) return false
        val address = runCatching { InetAddress.getByName(host) }.getOrNull() ?: return true
        return when (address) {
            is Inet4Address -> isForbiddenIPv4(address.address.map(Byte::toUByte))
            is Inet6Address -> isForbiddenIPv6(address.address.map(Byte::toUByte))
            else -> true
        }
    }

    private fun isForbiddenIPv4(bytes: List<UByte>): Boolean {
        if (bytes.size != 4) return true
        val first = bytes[0].toInt()
        val second = bytes[1].toInt()
        val third = bytes[2].toInt()
        return first == 0 || first == 10 || first == 127 || first >= 224 ||
            (first == 100 && second in 64..127) ||
            (first == 169 && second == 254) ||
            (first == 172 && second in 16..31) ||
            (first == 192 && second == 168) ||
            (first == 192 && second == 0 && (third == 0 || third == 2)) ||
            (first == 192 && second == 88 && third == 99) ||
            (first == 198 && second in 18..19) ||
            (first == 198 && second == 51 && third == 100) ||
            (first == 203 && second == 0 && third == 113)
    }

    private fun isForbiddenIPv6(bytes: List<UByte>): Boolean {
        if (bytes.size != 16) return true
        // Only global-unicast literals are accepted. Link-local, unique-local,
        // multicast, loopback, mapped IPv4 and unspecified ranges are reserved.
        if (bytes[0].toInt() and 0xE0 != 0x20) return true
        return bytes[0].toInt() == 0x20 && bytes[1].toInt() == 0x01 &&
            bytes[2].toInt() == 0x0D && bytes[3].toInt() == 0xB8
    }
}

internal object CustomDeadlineFeedParser {
    const val maximumItems = 5_000
    const val maximumItemsPerDay = 100
    const val maximumCalendarRangeDays = 370

    private val envelopeKeys = setOf("version", "source", "homepage", "updated_at", "items")
    private val itemKeys = setOf(
        "id", "name", "event_type", "primary_deadline", "organizer", "official_url",
    )

    fun parse(payload: String, sourceURL: String): ParsedCustomDeadlineFeed {
        val root = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("自定义日程 JSON 格式不正确。", error)
        }
        if (!keys(root).all(envelopeKeys::contains)) {
            throw DailyInfoClientException("自定义日程不符合 v1 接口规范。")
        }
        val version = root.opt("version")
        val sourceName = normalizedString(root.opt("source"), 80)
        val records = root.opt("items") as? JSONArray
        if (version !is Number || version.toInt() != 1 || version.toDouble() != 1.0 ||
            sourceName == null || records == null || records.length() > maximumItems
        ) {
            throw DailyInfoClientException("自定义日程不符合 v1 接口规范。")
        }
        val homepage = optionalSafeURL(root, "homepage", envelope = true)
        val updatedAt = if (root.has("updated_at")) {
            (root.opt("updated_at") as? String)?.takeIf(::isRFC3339WithTimeZone)
                ?: throw DailyInfoClientException("自定义日程更新时间格式不正确。")
        } else {
            null
        }
        val indexed = linkedMapOf<String, MutableList<PublicDeadlineItem>>()
        val seen = mutableSetOf<String>()
        for (index in 0 until records.length()) {
            val record = records.optJSONObject(index) ?: continue
            if (!keys(record).all(itemKeys::contains)) continue
            val id = normalizedString(record.opt("id"), 128) ?: continue
            val name = normalizedString(record.opt("name"), 200) ?: continue
            val kind = (record.opt("event_type") as? String)
                ?.let(PublicDeadlineKind::fromWireValue)
                ?: continue
            val deadline = (record.opt("primary_deadline") as? String)
                ?.takeIf(::isRFC3339WithTimeZone)
                ?: continue
            val date = deadline.take(10)
            if (!isContractDate(date)) continue
            val organizer = if (record.has("organizer")) {
                normalizedString(record.opt("organizer"), 200) ?: continue
            } else {
                null
            }
            val officialURL = optionalSafeURL(record, "official_url", envelope = false)
                ?: if (record.has("official_url")) continue else null
            val items = indexed.getOrPut(date) { mutableListOf() }
            if (items.size >= maximumItemsPerDay) continue
            val item = PublicDeadlineItem(
                id = id,
                name = name,
                kind = kind,
                source = PublicDeadlineSource.CUSTOM,
                deadline = deadline,
                organizer = organizer,
                officialURL = officialURL,
                sourceName = sourceName,
                sourceHomepage = homepage,
            )
            if (seen.add(item.favoriteID)) items += item
        }
        return ParsedCustomDeadlineFeed(
            sourceURL = CustomDeadlineFeedURLValidator.validatedURI(sourceURL).toString(),
            sourceName = sourceName,
            homepage = homepage,
            updatedAt = updatedAt,
            itemsByDate = indexed.mapValues { (_, items) ->
                items.sortedWith(compareBy(PublicDeadlineItem::deadline, PublicDeadlineItem::name))
            },
        )
    }

    private fun optionalSafeURL(source: JSONObject, key: String, envelope: Boolean): String? {
        if (!source.has(key)) return null
        val raw = source.opt(key) as? String
        val uri = raw?.let { runCatching { CustomDeadlineFeedURLValidator.validatedURI(it) }.getOrNull() }
        if (uri != null) return uri.toString()
        if (envelope) {
            throw DailyInfoClientException("自定义日程来源主页不是安全的 HTTPS URL。")
        }
        return null
    }

    private fun normalizedString(value: Any?, maximumLength: Int): String? =
        (value as? String)?.trim()?.takeIf { it.isNotEmpty() && it.length <= maximumLength }

    private fun keys(value: JSONObject): Set<String> = buildSet {
        val iterator = value.keys()
        while (iterator.hasNext()) add(iterator.next())
    }
}

internal object PublicDeadlineItemJsonCodec {
    fun encode(items: List<PublicDeadlineItem>): String = JSONArray().apply {
        items.forEach { item ->
            put(JSONObject().apply {
                put("id", item.id)
                put("name", item.name)
                put("event_type", item.kind.wireValue)
                put("source", item.source.wireValue)
                put("deadline", item.deadline)
                item.organizer?.let { put("organizer", it) }
                item.officialURL?.let { put("official_url", it) }
                item.sourceName?.let { put("source_name", it) }
                item.sourceHomepage?.let { put("source_homepage", it) }
                if (item.categories.isNotEmpty()) {
                    put("categories", JSONArray(item.categories))
                }
                if (item.tags.isNotEmpty()) put("tags", JSONArray(item.tags))
                item.level?.let { put("level", it) }
                item.location?.let { put("location", it) }
                item.description?.let { put("description", it) }
                item.eligibility?.let { put("eligibility", it) }
                item.notes?.let { put("notes", it) }
                item.metadataSource?.let { metadata ->
                    put("metadata_source", JSONObject().apply {
                        put("name", metadata.name)
                        metadata.url?.let { put("url", it) }
                        metadata.sourceType?.let { put("source_type", it) }
                        metadata.authority?.let { put("authority", it) }
                    })
                }
                item.status?.let { put("status", it) }
                item.region?.let { put("region", it) }
                item.mode?.let { put("mode", it) }
                if (item.archived) put("archived", true)
            })
        }
    }.toString()

    fun decode(payload: String?): List<PublicDeadlineItem> {
        if (payload.isNullOrBlank()) return emptyList()
        val records = runCatching { JSONArray(payload) }.getOrNull() ?: return emptyList()
        val seen = mutableSetOf<String>()
        return buildList {
            for (index in 0 until minOf(records.length(), AppPreferences.maximumFavoriteDeadlines)) {
                val record = records.optJSONObject(index) ?: continue
                val id = record.optString("id").trim().takeIf { it.isNotEmpty() && it.length <= 128 }
                    ?: continue
                val name = record.optString("name").trim().takeIf { it.isNotEmpty() && it.length <= 200 }
                    ?: continue
                val kind = PublicDeadlineKind.fromWireValue(record.optString("event_type"))
                    ?: continue
                val source = PublicDeadlineSource.fromWireValue(record.optString("source"))
                    ?: continue
                val deadline = record.optString("deadline").takeIf(::isRFC3339WithTimeZone)
                    ?: continue
                val organizer = record.optString("organizer").trim()
                    .takeIf { it.isNotEmpty() && it.length <= 200 }
                val officialURL = safeStoredOfficialURL(record, "official_url")
                    ?: if (record.has("official_url")) continue else null
                val sourceName = record.optString("source_name").trim()
                    .takeIf { it.isNotEmpty() && it.length <= 80 }
                val sourceHomepage = safeStoredURL(record, "source_homepage")
                    ?: if (record.has("source_homepage")) continue else null
                val categories = record.optJSONArray("categories")?.let { values ->
                    storedStringArray(values)
                }.orEmpty()
                val tags = record.optJSONArray("tags")?.let(::storedStringArray).orEmpty()
                val level = storedString(record, "level", 120)
                val location = storedString(record, "location", 240)
                val description = storedString(record, "description", 4_000)
                val eligibility = storedString(record, "eligibility", 500)
                val notes = storedString(record, "notes", 4_000)
                val metadataSource = storedMetadataSource(record.optJSONObject("metadata_source"))
                    ?: if (record.has("metadata_source")) continue else null
                val status = storedString(record, "status", 80)
                val region = storedString(record, "region", 80)
                val mode = storedString(record, "mode", 80)
                val archived = record.opt("archived") as? Boolean ?: false
                val item = PublicDeadlineItem(
                    id, name, kind, source, deadline, organizer, officialURL,
                    sourceName, sourceHomepage, categories, tags, level, location,
                    description, eligibility, notes, metadataSource, status, region,
                    mode, archived,
                )
                if (seen.add(item.favoriteID)) add(item)
            }
        }
    }

    private fun safeStoredURL(source: JSONObject, key: String): String? =
        source.optString(key).trim().takeIf(String::isNotEmpty)?.let { raw ->
            runCatching { CustomDeadlineFeedURLValidator.validatedURI(raw).toString() }.getOrNull()
        }

    private fun safeStoredOfficialURL(source: JSONObject, key: String): String? =
        source.optString(key).trim().takeIf(String::isNotEmpty)?.let { raw ->
            runCatching {
                val uri = URI.create(raw)
                raw.takeIf {
                    uri.scheme.equals("https", ignoreCase = true) &&
                        !uri.host.isNullOrBlank() && uri.userInfo == null
                }
            }.getOrNull()
        }

    private fun storedStringArray(values: JSONArray): List<String> = buildList {
        for (index in 0 until minOf(values.length(), 40)) {
            val value = values.opt(index) as? String ?: continue
            val normalized = value.trim()
            if (normalized.isNotEmpty() && normalized.length <= 120 && normalized !in this) {
                add(normalized)
            }
        }
    }

    private fun storedString(source: JSONObject, key: String, maximum: Int): String? =
        (source.opt(key) as? String)?.trim()
            ?.takeIf { it.isNotEmpty() && it.length <= maximum }

    private fun storedMetadataSource(source: JSONObject?): PublicDeadlineMetadataSource? {
        source ?: return null
        val name = storedString(source, "name", 120) ?: return null
        val url = safeStoredOfficialURL(source, "url")
            ?: if (source.has("url")) return null else null
        val sourceType = storedString(source, "source_type", 80)
        val authority = (source.opt("authority") as? Number)?.toInt()
            ?.takeIf { it in 0..100 }
        return PublicDeadlineMetadataSource(name, url, sourceType, authority)
    }
}

internal object CustomDeadlineFeedTransport {
    fun fetch(uri: URI, maximumBytes: Int = CalendarDailyInfoSources.deadlinePayloadLimit): String {
        CustomDeadlineFeedURLValidator.validate(uri)
        val connection = uri.toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.allowUserInteraction = false
            connection.doOutput = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Cookie", "")
            connection.setRequestProperty(
                "User-Agent",
                "WhereToStudyNative/${BuildConfig.VERSION_NAME}",
            )
            val status = connection.responseCode
            if (status in 300..399) {
                throw DailyInfoClientException("自定义日程返回了不受信任的重定向。")
            }
            if (status !in 200..299) {
                throw DailyInfoClientException("自定义日程返回 HTTP $status。")
            }
            if (connection.contentLengthLong > maximumBytes) {
                throw DailyInfoClientException("自定义日程响应超过 2 MiB。")
            }
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            connection.inputStream.use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    if (output.size() + count > maximumBytes) {
                        throw DailyInfoClientException("自定义日程响应超过 2 MiB。")
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

private fun isRFC3339WithTimeZone(value: String): Boolean {
    val match = Regex(
        "^(\\d{4}-\\d{2}-\\d{2})T(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d" +
            "(?:\\.\\d+)?(?:Z|[+-](?:[01]\\d|2[0-3]):[0-5]\\d)$",
    ).matchEntire(value) ?: return false
    return isContractDate(match.groupValues[1])
}

private fun isContractDate(value: String): Boolean {
    if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) return false
    val parser = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { isLenient = false }
    val position = ParsePosition(0)
    return parser.parse(value, position) != null && position.index == value.length
}
