package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import org.json.JSONArray
import org.json.JSONObject

object ClassroomsJsonCodec {
    fun decode(value: String): ClassroomsCache {
        val root = JSONObject(value)
        return ClassroomsCache(
            cacheVersion = root.getInt("cache_version"),
            targetDate = root.getString("target_date"),
            fetchedAt = root.getString("fetched_at"),
            realtime = root.optBoolean("realtime", true),
            provider = root.optString("provider", "sjd"),
            campuses = root.getJSONArray("campuses").objects().map(::decodeCampus),
        )
    }

    fun encode(cache: ClassroomsCache): String = JSONObject()
        .put("cache_version", cache.cacheVersion)
        .put("target_date", cache.targetDate)
        .put("fetched_at", cache.fetchedAt)
        .put("realtime", cache.realtime)
        .put("provider", cache.provider)
        .put("campuses", JSONArray().apply {
            cache.campuses.forEach { campus -> put(encodeCampus(campus)) }
        })
        .toString(2)

    private fun decodeCampus(value: JSONObject): CampusClassrooms = CampusClassrooms(
        campusID = value.getString("campus_id"),
        campusName = value.getString("campus_name"),
        targetDate = value.getString("target_date"),
        fetchedAt = value.getString("fetched_at"),
        realtime = value.optBoolean("realtime", true),
        provider = value.optString("provider", "sjd"),
        rooms = value.getJSONArray("rooms").objects().map(::decodeRoom),
    )

    private fun decodeRoom(value: JSONObject): Classroom = Classroom(
        id = value.getString("id"),
        building = value.getString("building"),
        room = value.getString("room"),
        name = value.getString("name"),
        size = if (value.isNull("size")) null else value.getInt("size"),
        type = value.optString("type"),
        availableSlots = value.getJSONArray("available_slots").integers(),
        source = value.optString("source", "sjd"),
    )

    private fun encodeCampus(campus: CampusClassrooms): JSONObject = JSONObject()
        .put("campus_id", campus.campusID)
        .put("campus_name", campus.campusName)
        .put("target_date", campus.targetDate)
        .put("fetched_at", campus.fetchedAt)
        .put("realtime", campus.realtime)
        .put("provider", campus.provider)
        .put("rooms", JSONArray().apply {
            campus.rooms.forEach { room -> put(encodeRoom(room)) }
        })

    private fun encodeRoom(room: Classroom): JSONObject = JSONObject()
        .put("id", room.id)
        .put("building", room.building)
        .put("room", room.room)
        .put("name", room.name)
        .put("size", room.size ?: JSONObject.NULL)
        .put("type", room.type)
        .put("available_slots", JSONArray(room.availableSlots))
        .put("source", room.source)

    private fun JSONArray.objects(): List<JSONObject> =
        (0 until length()).map(::getJSONObject)

    private fun JSONArray.integers(): List<Int> =
        (0 until length()).map(::getInt)
}

class ClassroomStore(context: Context) {
    private val file = AtomicFile(File(context.filesDir, FILE_NAME))

    fun load(): ClassroomsCache? {
        if (!file.baseFile.exists()) return null
        val content = file.openRead().bufferedReader(StandardCharsets.UTF_8).use { it.readText() }
        if (content.isBlank()) return null
        return ClassroomsJsonCodec.decode(content)
            .takeIf { it.cacheVersion >= AppMetadata.classroomsCacheVersion }
    }

    fun save(cache: ClassroomsCache) {
        val output = file.startWrite()
        try {
            val writer = OutputStreamWriter(output, StandardCharsets.UTF_8)
            writer.write(ClassroomsJsonCodec.encode(cache))
            writer.flush()
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    private companion object {
        const val FILE_NAME = "classrooms.json"
    }
}
