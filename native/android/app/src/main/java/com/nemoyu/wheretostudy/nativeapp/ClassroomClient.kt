package com.nemoyu.wheretostudy.nativeapp

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

class ClassroomClientException(
    message: String,
    val retryable: Boolean = false,
) : Exception(message)

class SjdClassroomClient(
    private val api: SjdApiClient = SjdApiClient(),
) {
    fun fetch(
        credentials: Credentials,
        targetDate: String = contractDate(Date()),
        fetchedAt: String = timestamp(Date()),
    ): ClassroomsCache {
        if (targetDate != contractDate(Date())) {
            throw ClassroomClientException("空教室实时接口仅支持当天查询。")
        }
        val token = api.login(credentials)
        val payloads = AppMetadata.campuses.associate { campus ->
            val payload = api.get(
                path = "/bjyddx/todayClassrooms",
                referer = SjdApiClient.CLASSROOM_REFERER,
                query = mapOf("campusId" to campus.id),
                token = token,
            )
            if (!api.isSuccessful(payload)) {
                throw ClassroomClientException(
                    "${campus.name}校区实时教室数据获取失败：" +
                        api.message(payload, "实时教室数据获取失败。"),
                )
            }
            campus.id to payload
        }
        return SjdClassroomParser.parse(payloads, targetDate, fetchedAt)
    }

    private companion object {
        val shanghai: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")

        fun contractDate(date: Date): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = shanghai
        }.format(date)

        fun timestamp(date: Date): String = SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            Locale.US,
        ).apply { timeZone = shanghai }.format(date)
    }
}

object SjdClassroomParser {
    private data class ParsedClassroom(
        val building: String,
        val room: String,
        val size: Int?,
    )

    private data class RoomAccumulator(
        val id: String,
        val building: String,
        val room: String,
        val name: String,
        var size: Int?,
        val availableSlots: MutableSet<Int> = sortedSetOf(),
    )

    fun parse(
        payloads: Map<String, JSONObject>,
        targetDate: String,
        fetchedAt: String,
    ): ClassroomsCache {
        val campuses = AppMetadata.campuses.map { campus ->
            val payload = payloads[campus.id]
                ?: throw ClassroomClientException("缺少${campus.name}校区实时教室数据。")
            if (payload.opt("code").classroomStringValue() != "1") {
                throw ClassroomClientException("${campus.name}校区实时教室数据格式不正确。")
            }
            parseCampus(campus, payload.optJSONArray("data") ?: JSONArray(), targetDate, fetchedAt)
        }
        return ClassroomsCache(
            cacheVersion = AppMetadata.classroomsCacheVersion,
            targetDate = targetDate,
            fetchedAt = fetchedAt,
            realtime = true,
            provider = "sjd",
            campuses = campuses,
        )
    }

    private fun parseCampus(
        campus: CampusMetadata,
        items: JSONArray,
        targetDate: String,
        fetchedAt: String,
    ): CampusClassrooms {
        val roomMap = mutableMapOf<String, RoomAccumulator>()
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val nodeName = listOf("NODENAME", "nodeName", "nodename")
                .firstNotNullOfOrNull { key -> item.opt(key).classroomStringValue().ifEmpty { null } }
                ?: continue
            val slot = nodeNameToSlot(nodeName) ?: continue
            val classrooms = listOf("CLASSROOMS", "classrooms", "Classrooms")
                .firstNotNullOfOrNull { key -> item.opt(key).classroomStringValue().ifEmpty { null } }
                .orEmpty()
            classrooms.split(',').map(String::trim).filter(String::isNotEmpty).forEach { raw ->
                val parsed = parseClassroom(raw) ?: return@forEach
                val inferred = inferTeachingExperimentSide(
                    normalizeBuildingName(parsed.building),
                    parsed.room,
                )
                val building = inferred.first
                if (building !in originalBuildings) return@forEach
                val room = extractRoomName(inferred.second, building) ?: return@forEach
                val key = "$building-$room"
                val accumulator = roomMap.getOrPut(key) {
                    RoomAccumulator(key, building, room, key, parsed.size)
                }
                if (accumulator.size == null) accumulator.size = parsed.size
                accumulator.availableSlots += slot
            }
        }
        val rooms = roomMap.values.map { item ->
            Classroom(
                id = item.id,
                building = item.building,
                room = item.room,
                name = item.name,
                size = item.size,
                type = "",
                availableSlots = item.availableSlots.toList(),
                source = "sjd",
            )
        }.sortedWith(compareBy(Classroom::building, Classroom::room))
        return CampusClassrooms(
            campusID = campus.id,
            campusName = campus.name,
            targetDate = targetDate,
            fetchedAt = fetchedAt,
            realtime = true,
            provider = "sjd",
            rooms = rooms,
        )
    }

    private fun parseClassroom(raw: String): ParsedClassroom? {
        var clean = raw.trim()
        if (clean.isEmpty()) return null
        val sizeMatch = sizePattern.find(clean)
        val size = sizeMatch?.groupValues?.getOrNull(1)?.toIntOrNull()
        if (sizeMatch != null) clean = clean.substring(0, sizeMatch.range.first).trim()
        clean = normalizeSeparators(clean)
        val parts = clean.split('-').map(String::trim).filter(String::isNotEmpty)
        val building: String
        val room: String
        if (parts.size >= 3 && parts.first() in campusPrefixes) {
            val roomStart = clean.indexOf(parts[2]).takeIf { it >= 0 } ?: clean.length
            building = clean.substring(0, roomStart).trimEnd('-').trim()
            room = clean.substring(roomStart.coerceAtMost(clean.length)).trim()
        } else {
            val separator = clean.indexOf('-')
            if (separator >= 0) {
                building = clean.substring(0, separator).trim()
                room = clean.substring(separator + 1).trim()
            } else {
                building = "未知教学楼"
                room = clean
            }
        }
        return ParsedClassroom(
            building = building.ifEmpty { "未知教学楼" },
            room = room.ifEmpty { clean },
            size = size,
        )
    }

    private fun normalizeBuildingName(value: String): String {
        val normalized = normalizeSeparators(value.trim())
        val clean = campusPrefixes.asSequence()
            .map { "$it-" }
            .firstNotNullOfOrNull { prefix -> normalized.removePrefix(prefix).takeIf { it != normalized } }
            ?.trim() ?: normalized.trim()
        val compact = clean.replace(" ", "").replace("　", "")
        return when {
            compact in setOf("1", "教一楼") -> "教1"
            compact in setOf("2", "教二楼") -> "教2"
            compact in setOf("3", "教三楼") -> "教3"
            compact in setOf("4", "教四楼") -> "教4"
            compact == "未来学习大楼" -> "主楼"
            compact in northBuildings -> "综合教学楼N"
            compact in southBuildings -> "综合教学楼S"
            compact in experimentNorthBuildings -> "教学实验综合楼N"
            compact in experimentSouthBuildings -> "教学实验综合楼S"
            compact in setOf("智慧楼", "智慧教室楼", "智慧教室") -> "智慧教学楼"
            clean.isEmpty() -> "未知教学楼"
            else -> clean
        }
    }

    private fun inferTeachingExperimentSide(building: String, roomName: String): Pair<String, String> {
        if (building != "教学实验综合楼") return building to roomName
        val cleanRoom = normalizeSeparators(roomName.trim()).replace(" ", "").replace("　", "")
        val side = cleanRoom.firstOrNull() ?: return building to roomName
        val rest = cleanRoom.drop(1).trimStart('-')
        if (rest.isEmpty() || !rest.first().isDigit()) return building to roomName
        return when (side) {
            'N', 'n', '北' -> "教学实验综合楼N" to rest
            'S', 's', '南' -> "教学实验综合楼S" to rest
            else -> building to roomName
        }
    }

    private fun extractRoomName(value: String, building: String): String? {
        var clean = normalizeSeparators(value.trim())
        val buildingNumber = building.removePrefix("教").takeIf { building.startsWith("教") }
        if (buildingNumber != null) {
            clean = when {
                clean.startsWith("$buildingNumber-") -> clean.removePrefix("$buildingNumber-").trim()
                clean.startsWith("教$buildingNumber-") -> clean.removePrefix("教$buildingNumber-").trim()
                else -> clean
            }
        }
        return roomPattern.find(clean)?.value
    }

    private fun nodeNameToSlot(value: String): Int? {
        val node = numberPattern.find(value.trim())?.value?.toIntOrNull() ?: return null
        return node.takeIf { it in 1..14 }?.minus(1)
    }

    private fun normalizeSeparators(value: String): String = value
        .replace('－', '-')
        .replace('—', '-')
        .replace('–', '-')

    private val sizePattern = Regex("""[（(]\s*(\d+)\s*[）)]""")
    private val roomPattern = Regex("""\d{3}(?:-\d{3})?""")
    private val numberPattern = Regex("""\d+""")
    private val campusPrefixes = setOf("校本部", "西土城", "沙河")
    private val originalBuildings = setOf(
        "教1", "教2", "教3", "教4", "主楼", "综合教学楼N", "综合教学楼S",
        "教学实验综合楼N", "教学实验综合楼S", "智慧教学楼",
    )
    private val northBuildings = setOf(
        "N", "N楼", "N座", "北楼", "综合教学楼N", "综合教学楼N楼", "综合教学楼N座",
        "综合楼N", "综合楼N楼", "综合N",
    )
    private val southBuildings = setOf(
        "S", "S楼", "S座", "南楼", "综合教学楼S", "综合教学楼S楼", "综合教学楼S座",
        "综合楼S", "综合楼S楼", "综合S",
    )
    private val experimentNorthBuildings = setOf(
        "教学实验综合楼N", "教学实验综合楼N楼", "教学实验综合楼N座", "教学实验综合楼北",
        "教学实验综合楼北楼", "教学实验综合楼-N", "教学实验综合楼-N楼",
        "教学实验综合楼(综教)N", "教学实验综合楼（综教）N", "教学实验综合楼N(综教)",
        "教学实验综合楼N（综教）", "综教N", "综教N楼", "综教N座", "综教北", "综教北楼",
        "综教-N", "综教-N楼",
    )
    private val experimentSouthBuildings = setOf(
        "教学实验综合楼S", "教学实验综合楼S楼", "教学实验综合楼S座", "教学实验综合楼南",
        "教学实验综合楼南楼", "教学实验综合楼-S", "教学实验综合楼-S楼",
        "教学实验综合楼(综教)S", "教学实验综合楼（综教）S", "教学实验综合楼S(综教)",
        "教学实验综合楼S（综教）", "综教S", "综教S楼", "综教S座", "综教南", "综教南楼",
        "综教-S", "综教-S楼",
    )
}

private fun Any?.classroomStringValue(): String = when (this) {
    null, JSONObject.NULL -> ""
    is String -> this
    is Number -> toString()
    else -> toString()
}
