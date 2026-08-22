package com.nemoyu.wheretostudy.nativeapp

import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

data class CampusWeatherDay(
    val date: String,
    val weekday: String,
    val weatherDay: String,
    val weatherNight: String,
    val temperatureMaximum: Int,
    val temperatureMinimum: Int,
    val precipitationProbability: Int?,
)

data class CampusWeather(
    val campusID: String,
    val campusName: String,
    val district: String,
    val currentWeather: String,
    val currentTemperature: Int,
    val reportTime: String,
    val days: List<CampusWeatherDay>,
)

class DailyInfoClientException(message: String, cause: Throwable? = null) : Exception(message, cause)

internal data class CampusWeatherTarget(
    val campusID: String,
    val campusName: String,
    val adcode: String,
)

internal object CampusWeatherTargets {
    fun resolve(campusID: String): CampusWeatherTarget = when (campusID.trim()) {
        "01", "1" -> CampusWeatherTarget("01", "西土城", "110108")
        "04", "4" -> CampusWeatherTarget("04", "沙河", "110114")
        else -> throw DailyInfoClientException("暂不支持该校区的天气查询。")
    }
}

internal object DailyInfoLimits {
    const val source = "https://uapis.cn"
    const val sourceHost = "uapis.cn"
    const val maximumPayloadBytes = 128 * 1024
    const val maximumRedirects = 5
}

internal object WeatherResponseParser {
    private val contractDatePattern = Regex("\\d{4}-\\d{2}-\\d{2}")
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun parse(payload: String, campusID: String, campusName: String): CampusWeather {
        if (payload.toByteArray(StandardCharsets.UTF_8).size > DailyInfoLimits.maximumPayloadBytes) {
            throw DailyInfoClientException("生活信息响应过大。")
        }
        val source = try {
            JSONObject(payload)
        } catch (error: Exception) {
            throw DailyInfoClientException("天气数据格式不正确。", error)
        }
        val district = requiredString(source, "district")
        val currentWeather = requiredString(source, "weather")
        val reportTime = requiredString(source, "report_time")
        val currentTemperature = roundedTemperature(requiredNumber(source, "temperature"))
        val forecast = source.opt("forecast") as? JSONArray
            ?: throw DailyInfoClientException("天气数据格式不正确。")
        if (forecast.length() < 2) {
            throw DailyInfoClientException("天气数据缺少今日或明日信息。")
        }
        val days = (0 until 2).map { index ->
            val item = forecast.optJSONObject(index)
                ?: throw DailyInfoClientException("天气数据格式不正确。")
            val date = requiredString(item, "date")
            if (!isValidDate(date)) {
                throw DailyInfoClientException("天气数据日期格式不正确。")
            }
            val probability = when (val value = item.opt("pop")) {
                null, JSONObject.NULL -> null
                is Number -> roundedProbability(value.toDouble())
                else -> throw DailyInfoClientException("天气降水概率格式不正确。")
            }
            CampusWeatherDay(
                date = date,
                weekday = requiredString(item, "week"),
                weatherDay = requiredString(item, "weather_day"),
                weatherNight = requiredString(item, "weather_night"),
                temperatureMaximum = roundedTemperature(requiredNumber(item, "temp_max")),
                temperatureMinimum = roundedTemperature(requiredNumber(item, "temp_min")),
                precipitationProbability = probability,
            )
        }
        return CampusWeather(
            campusID = campusID,
            campusName = campusName,
            district = district,
            currentWeather = currentWeather,
            currentTemperature = currentTemperature,
            reportTime = reportTime,
            days = days,
        )
    }

    private fun requiredString(objectValue: JSONObject, key: String): String {
        val value = objectValue.opt(key) as? String
            ?: throw DailyInfoClientException("天气数据格式不正确。")
        return value.trim().takeIf(String::isNotEmpty)
            ?: throw DailyInfoClientException("天气数据缺少今日或明日信息。")
    }

    private fun requiredNumber(objectValue: JSONObject, key: String): Double {
        val value = objectValue.opt(key) as? Number
            ?: throw DailyInfoClientException("天气数据格式不正确。")
        return value.toDouble()
    }

    private fun roundedTemperature(value: Double): Int {
        if (!value.isFinite() || value !in -150.0..100.0) {
            throw DailyInfoClientException("天气温度超出合理范围。")
        }
        return value.roundToInt()
    }

    private fun roundedProbability(value: Double): Int {
        if (!value.isFinite() || value !in 0.0..100.0) {
            throw DailyInfoClientException("天气降水概率超出合理范围。")
        }
        return value.roundToInt()
    }

    private fun isValidDate(value: String): Boolean {
        if (!contractDatePattern.matches(value)) return false
        return runCatching {
            SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                timeZone = shanghai
                isLenient = false
            }.parse(value) ?: error("invalid date")
        }.isSuccess
    }
}

class UapiWeatherClient(
    private val source: String = DailyInfoLimits.source,
) {
    fun fetch(campusID: String): CampusWeather {
        val target = CampusWeatherTargets.resolve(campusID)
        val initial = URI.create(
            "$source/api/v1/misc/weather?adcode=${target.adcode}&lang=zh&forecast=true",
        )
        val payload = fetchPayload(initial)
        return WeatherResponseParser.parse(payload, target.campusID, target.campusName)
    }

    private fun fetchPayload(initial: URI): String {
        var current = initial
        try {
            repeat(DailyInfoLimits.maximumRedirects + 1) {
                validate(current)
                val connection = current.toURL().openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 10_000
                    connection.readTimeout = 15_000
                    connection.instanceFollowRedirects = false
                    connection.doInput = true
                    connection.setRequestProperty("Accept", "application/json")
                    connection.setRequestProperty(
                        "User-Agent",
                        "WhereToStudyNative/${BuildConfig.VERSION_NAME}",
                    )
                    val status = connection.responseCode
                    if (status in 300..399) {
                        val location = connection.getHeaderField("Location")
                            ?: throw DailyInfoClientException("生活信息接口重定向地址无效。")
                        current = current.resolve(location)
                        return@repeat
                    }
                    if (status !in 200..299) {
                        throw DailyInfoClientException("生活信息接口返回错误，HTTP $status。")
                    }
                    return readResponse(connection)
                } finally {
                    connection.disconnect()
                }
            }
            throw DailyInfoClientException("生活信息接口重定向次数过多。")
        } catch (error: DailyInfoClientException) {
            throw error
        } catch (error: Exception) {
            throw DailyInfoClientException("无法获取天气信息，请稍后重试。", error)
        }
    }

    private fun validate(uri: URI) {
        val port = if (uri.port == -1) 443 else uri.port
        if (uri.scheme?.lowercase(Locale.US) != "https" ||
            uri.host?.lowercase(Locale.US) != DailyInfoLimits.sourceHost ||
            port != 443 ||
            uri.userInfo != null
        ) {
            throw DailyInfoClientException("生活信息接口重定向目标不受信任。")
        }
    }

    private fun readResponse(connection: HttpURLConnection): String {
        if (connection.contentLengthLong > DailyInfoLimits.maximumPayloadBytes) {
            throw DailyInfoClientException("生活信息响应过大。")
        }
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        connection.inputStream.use { input ->
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                if (output.size() + count > DailyInfoLimits.maximumPayloadBytes) {
                    throw DailyInfoClientException("生活信息响应过大。")
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
            throw DailyInfoClientException("生活信息响应编码不正确。", error)
        }
    }
}

class WeatherRepository(
    private val client: UapiWeatherClient = UapiWeatherClient(),
    private val usesSampleData: Boolean = DailyCourseNotificationRuntimeMode.isUiTesting,
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val weatherByCampus = ConcurrentHashMap<String, CampusWeather>()
    private val errorsByCampus = ConcurrentHashMap<String, String>()
    private val loadingCampuses = ConcurrentHashMap.newKeySet<String>()
    private val closed = AtomicBoolean(false)

    fun weather(campusID: String): CampusWeather? = weatherByCampus[campusID]

    fun error(campusID: String): String? = errorsByCampus[campusID]

    fun isLoading(campusID: String): Boolean = campusID in loadingCampuses

    fun load(campusID: String, force: Boolean = false, onComplete: () -> Unit) {
        if (closed.get()) return
        if (!force && weatherByCampus[campusID] != null) return
        if (!loadingCampuses.add(campusID)) return
        errorsByCampus.remove(campusID)
        try {
            worker.execute {
                val result = runCatching {
                    if (usesSampleData) sampleWeather(campusID) else client.fetch(campusID)
                }
                result.onSuccess { weatherByCampus[campusID] = it }
                    .onFailure { errorsByCampus[campusID] = it.message ?: "天气获取失败。" }
                loadingCampuses.remove(campusID)
                if (!closed.get()) mainHandler.post { if (!closed.get()) onComplete() }
            }
        } catch (_: RejectedExecutionException) {
            loadingCampuses.remove(campusID)
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)
        worker.shutdownNow()
    }

    private fun sampleWeather(campusID: String): CampusWeather {
        val target = CampusWeatherTargets.resolve(campusID)
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }
        val today = Date()
        val tomorrow = Date(today.time + 24 * 60 * 60 * 1000L)
        return CampusWeather(
            campusID = target.campusID,
            campusName = target.campusName,
            district = if (target.campusID == "01") "海淀区" else "昌平区",
            currentWeather = "多云",
            currentTemperature = 27,
            reportTime = "示例数据",
            days = listOf(
                CampusWeatherDay(date.format(today), "今天", "多云", "雷阵雨", 32, 23, 40),
                CampusWeatherDay(date.format(tomorrow), "明天", "晴", "多云", 33, 22, 10),
            ),
        )
    }
}
