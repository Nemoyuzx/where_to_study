package com.nemoyu.wheretostudy.nativeapp

import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject

internal class UCloudAssignmentClient(
    private val credentialStore: SecureCredentialStore,
) {
    private data class CachedAssignments(
        val account: String,
        val fetchedAtElapsed: Long,
        val items: List<AssignmentDeadlineItem>,
    )

    private data class AuthenticatedSession(
        val accessToken: String,
        val userID: String,
    )

    private data class HTTPResult(
        val status: Int,
        val headers: Map<String, List<String>>,
        val body: String,
    )

    @Volatile
    private var cachedAssignments: CachedAssignments? = null
    private val revision = AtomicLong(0)

    fun fetch(date: String): List<AssignmentDeadlineItem> {
        requireUCloudDate(date)
        val credentials = credentialStore.load()
            ?.takeIf { it.account.trim().isNotEmpty() && it.password.isNotEmpty() }
            ?: throw DailyInfoClientException("请先在设置中保存教务账号和密码。")
        val account = credentials.account.trim()
        val cached = cachedAssignments
        val allItems = if (cached != null && cached.account == account &&
            SystemClock.elapsedRealtime() - cached.fetchedAtElapsed < CACHE_LIFETIME_MS
        ) {
            cached.items
        } else {
            val requestRevision = revision.get()
            fetchAll(Credentials(account, credentials.password)).also { items ->
                if (revision.get() == requestRevision) {
                    cachedAssignments = CachedAssignments(
                        account,
                        SystemClock.elapsedRealtime(),
                        items,
                    )
                }
            }
        }
        return allItems.filter { it.deadline.startsWith(date) }
    }

    fun reset() {
        revision.incrementAndGet()
        cachedAssignments = null
    }

    private fun fetchAll(credentials: Credentials): List<AssignmentDeadlineItem> {
        val authenticated = authenticate(credentials)
        val courseRoot = apiGet(
            "/ykt-site/site/list/student/current",
            mapOf(
                "size" to "9999",
                "current" to "1",
                "userId" to authenticated.userID,
                "siteRoleCode" to "2",
            ),
            authenticated,
        )
        val courses = courseRecords(courseRoot).take(MAXIMUM_COURSES)
        val allItems = mutableListOf<AssignmentDeadlineItem>()
        var successfulCourseRequests = 0
        var firstCourseError: Exception? = null
        courses.forEach { course ->
            if (allItems.size >= MAXIMUM_ASSIGNMENTS) return@forEach
            val body = JSONObject()
                .put("siteId", course.first)
                .put("userId", authenticated.userID)
                .put("keyword", "")
                .put("chapterId", "")
                .put("nodeId", "")
                .put("current", 1)
                .put("size", 9999)
                .put("studentAssignmentStatus", "")
                .put("status", "")
                .put("sortColumn", "")
                .put("sortType", "")
            try {
                val root = apiPost(
                    "/ykt-site/work/student/list",
                    body,
                    authenticated,
                )
                successfulCourseRequests += 1
                allItems += AssignmentDeadlineResponseParser.parseAll(root, course.second)
            } catch (error: Exception) {
                if (firstCourseError == null) firstCourseError = error
            }
        }
        if (courses.isNotEmpty() && successfulCourseRequests == 0) {
            throw firstCourseError
                ?: DailyInfoClientException("教学云课程作业接口暂时不可用。")
        }

        runCatching {
            apiGet(
                "/ykt-site/site/student/undone",
                mapOf("userId" to authenticated.userID),
                authenticated,
            )
        }.onSuccess { root ->
            allItems += AssignmentDeadlineResponseParser.parseAll(root, null)
        }
        return merge(allItems)
    }

    private fun authenticate(credentials: Credentials): AuthenticatedSession {
        val loginPage = execute(
            URI.create(CAS_LOGIN_URL),
            method = "GET",
            headers = mapOf("Accept" to "text/html"),
            body = null,
            maximumBytes = MAXIMUM_LOGIN_BYTES,
            expectedHost = "auth.bupt.edu.cn",
            acceptedStatus = 200..299,
        )
        val execution = parseExecution(loginPage.body)
            ?: throw DailyInfoClientException("统一认证登录页缺少 execution 参数。")
        val cookies = loginPage.headers.entries
            .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
            .flatMap { it.value }
            .map { it.substringBefore(';').trim() }
            .filter(String::isNotEmpty)
            .joinToString("; ")
        if (cookies.isEmpty() || cookies.toByteArray(StandardCharsets.UTF_8).size > MAXIMUM_COOKIE_BYTES) {
            throw DailyInfoClientException("统一认证未返回有效会话 Cookie。")
        }

        val loginResult = execute(
            URI.create(CAS_LOGIN_URL),
            method = "POST",
            headers = mapOf(
                "Content-Type" to "application/x-www-form-urlencoded",
                "Cookie" to cookies,
                "Referer" to CAS_LOGIN_URL,
            ),
            body = formBody(
                "username" to credentials.account,
                "password" to credentials.password,
                "type" to "username_password",
                "execution" to execution,
                "_eventId" to "submit",
            ),
            maximumBytes = MAXIMUM_LOGIN_BYTES,
            expectedHost = "auth.bupt.edu.cn",
            acceptedStatus = 200..399,
        )
        val location = loginResult.headers.entries
            .firstOrNull { it.key.equals("Location", ignoreCase = true) }
            ?.value?.firstOrNull()
            .orEmpty()
        val ticket = ticketFrom(location)
            ?: throw DailyInfoClientException(
                "统一认证未返回有效票据；请检查账号密码，若官方页面要求验证码请先完成验证。",
            )

        val tokenResult = execute(
            trustedAPIURI("/ykt-basics/oauth/token"),
            method = "POST",
            headers = apiHeaders(null) +
                ("Content-Type" to "application/x-www-form-urlencoded"),
            body = formBody("ticket" to ticket, "grant_type" to "third"),
            maximumBytes = MAXIMUM_TOKEN_BYTES,
            expectedHost = API_HOST,
            acceptedStatus = 200..299,
        )
        val tokenRoot = runCatching { JSONObject(tokenResult.body) }
            .getOrElse { throw DailyInfoClientException("教学云令牌接口数据格式不正确。", it) }
        val accessToken = stringValue(tokenRoot.opt("access_token"))
            ?: throw DailyInfoClientException("教学云令牌接口未返回访问令牌。")
        val userID = stringValue(tokenRoot.opt("user_id") ?: tokenRoot.opt("userId"))
            ?: throw DailyInfoClientException("教学云令牌接口未返回用户标识。")
        return AuthenticatedSession(accessToken, userID)
    }

    private fun apiGet(
        path: String,
        query: Map<String, String>,
        authenticated: AuthenticatedSession,
    ): JSONObject {
        val queryText = query.entries.joinToString("&") {
            "${encode(it.key)}=${encode(it.value)}"
        }
        return apiRoot(
            execute(
                trustedAPIURI("$path?$queryText"),
                method = "GET",
                headers = apiHeaders(authenticated.accessToken),
                body = null,
                maximumBytes = MAXIMUM_API_BYTES,
                expectedHost = API_HOST,
                acceptedStatus = 200..299,
            ),
        )
    }

    private fun apiPost(
        path: String,
        body: JSONObject,
        authenticated: AuthenticatedSession,
    ): JSONObject = apiRoot(
        execute(
            trustedAPIURI(path),
            method = "POST",
            headers = apiHeaders(authenticated.accessToken) +
                ("Content-Type" to "application/json"),
            body = body.toString(),
            maximumBytes = MAXIMUM_API_BYTES,
            expectedHost = API_HOST,
            acceptedStatus = 200..299,
        ),
    )

    private fun apiRoot(result: HTTPResult): JSONObject {
        val root = runCatching { JSONObject(result.body) }
            .getOrElse { throw DailyInfoClientException("教学云数据接口没有返回有效 JSON。", it) }
        if (root.has("code") && stringValue(root.opt("code")) != "200") {
            throw DailyInfoClientException(
                "教学云数据接口返回业务状态 ${stringValue(root.opt("code")) ?: "unknown"}。",
            )
        }
        return root
    }

    private fun execute(
        uri: URI,
        method: String,
        headers: Map<String, String>,
        body: String?,
        maximumBytes: Int,
        expectedHost: String,
        acceptedStatus: IntRange,
    ): HTTPResult {
        requireTrustedHTTPS(uri, expectedHost)
        val connection = uri.toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 8_000
            connection.readTimeout = 20_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty(
                "User-Agent",
                "WhereToStudyNative/${BuildConfig.VERSION_NAME}",
            )
            headers.forEach(connection::setRequestProperty)
            if (body != null) {
                connection.doOutput = true
                val bytes = body.toByteArray(StandardCharsets.UTF_8)
                try {
                    connection.setFixedLengthStreamingMode(bytes.size)
                    connection.outputStream.use { it.write(bytes) }
                } finally {
                    bytes.fill(0)
                }
            }
            val status = connection.responseCode
            if (status in 300..399 && status !in acceptedStatus) {
                throw DailyInfoClientException("教学云接口返回了不受信任的重定向。")
            }
            if (status !in acceptedStatus) {
                throw DailyInfoClientException("教学云接口返回 HTTP $status。")
            }
            if (connection.contentLengthLong > maximumBytes) {
                throw DailyInfoClientException("教学云接口响应过大。")
            }
            val source = when {
                status in 300..399 -> null
                status >= 400 -> connection.errorStream
                else -> connection.inputStream
            }
            val output = ByteArrayOutputStream()
            if (source != null) {
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                source.use { input ->
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        if (output.size() + count > maximumBytes) {
                            throw DailyInfoClientException("教学云接口响应过大。")
                        }
                        output.write(buffer, 0, count)
                    }
                }
            }
            val headerFields = connection.headerFields.entries
                .filter { it.key != null }
                .associate { it.key to (it.value ?: emptyList()) }
            return HTTPResult(
                status,
                headerFields,
                output.toString(StandardCharsets.UTF_8.name()),
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun apiHeaders(accessToken: String?): Map<String, String> = buildMap {
        put("Accept", "application/json, text/plain, */*")
        put("Authorization", PORTAL_AUTHORIZATION)
        put("Tenant-Id", "000000")
        put("Referer", "$SERVICE_ORIGIN/")
        if (accessToken != null) put("Blade-Auth", accessToken)
    }

    private fun trustedAPIURI(path: String): URI {
        val uri = URI.create(API_ORIGIN).resolve(path)
        requireTrustedHTTPS(uri, API_HOST)
        return uri
    }

    private fun requireTrustedHTTPS(uri: URI, expectedHost: String) {
        val effectivePort = if (uri.port == -1) 443 else uri.port
        if (!uri.scheme.equals("https", ignoreCase = true) ||
            !uri.host.equals(expectedHost, ignoreCase = true) ||
            effectivePort != 443 || uri.userInfo != null
        ) {
            throw DailyInfoClientException("教学云接口地址不受信任。")
        }
    }

    private fun courseRecords(root: JSONObject): List<Pair<String, String?>> {
        val firstData = root.optJSONObject("data") ?: root
        val secondData = firstData.optJSONObject("data") ?: firstData
        val records = secondData.optJSONArray("records") ?: JSONArray()
        return (0 until records.length()).mapNotNull { index ->
            val record = records.optJSONObject(index) ?: return@mapNotNull null
            val id = firstValue(record, "id", "siteId", "courseId")
                ?: return@mapNotNull null
            id to firstValue(record, "siteName", "courseName", "siteTitle", "name")
        }
    }

    private fun merge(items: List<AssignmentDeadlineItem>): List<AssignmentDeadlineItem> {
        val merged = linkedMapOf<String, AssignmentDeadlineItem>()
        items.take(MAXIMUM_ASSIGNMENTS).forEach { item ->
            val key = "${item.id}\u001F${item.deadline}"
            val existing = merged[key]
            if (existing == null || (existing.courseName == null && item.courseName != null)) {
                merged[key] = item
            }
        }
        return merged.values.sortedWith(
            compareBy(
                AssignmentDeadlineItem::deadline,
                { it.courseName.orEmpty() },
                AssignmentDeadlineItem::title,
                AssignmentDeadlineItem::id,
            ),
        )
    }

    private fun firstValue(source: JSONObject, vararg keys: String): String? =
        keys.firstNotNullOfOrNull { stringValue(source.opt(it)) }

    companion object {
        private const val CAS_LOGIN_URL =
            "https://auth.bupt.edu.cn/authserver/login?service=https%3A%2F%2Fucloud.bupt.edu.cn"
        private const val SERVICE_ORIGIN = "https://ucloud.bupt.edu.cn"
        private const val API_ORIGIN = "https://apiucloud.bupt.edu.cn"
        private const val API_HOST = "apiucloud.bupt.edu.cn"
        private const val PORTAL_AUTHORIZATION =
            "Basic  cG9ydGFsOnBvcnRhbF9zZWNyZXQ="
        private const val MAXIMUM_LOGIN_BYTES = 1 * 1024 * 1024
        private const val MAXIMUM_TOKEN_BYTES = 512 * 1024
        private const val MAXIMUM_API_BYTES = 8 * 1024 * 1024
        private const val MAXIMUM_COOKIE_BYTES = 16 * 1024
        private const val MAXIMUM_COURSES = 100
        private const val MAXIMUM_ASSIGNMENTS = 5_000
        private const val CACHE_LIFETIME_MS = 10 * 60 * 1_000L

        internal fun parseExecution(html: String): String? {
            val inputRegex = Regex("""<input\b[^>]*>""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
            val attributeRegex = Regex(
                """\b(name|value)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))""",
                setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
            )
            for (inputMatch in inputRegex.findAll(html)) {
                var name: String? = null
                var value: String? = null
                for (attribute in attributeRegex.findAll(inputMatch.value)) {
                    val rawValue = attribute.groupValues.drop(2).firstOrNull(String::isNotEmpty)
                        ?: continue
                    when (attribute.groupValues[1].lowercase()) {
                        "name" -> name = decodeHTMLEntities(rawValue)
                        "value" -> value = decodeHTMLEntities(rawValue)
                    }
                }
                if (name == "execution" && !value.isNullOrEmpty()) return value
            }
            return null
        }

        internal fun ticketFrom(location: String): String? = runCatching {
            val uri = URI.create(SERVICE_ORIGIN).resolve(location)
            val effectivePort = if (uri.port == -1) 443 else uri.port
            if (!uri.scheme.equals("https", ignoreCase = true) ||
                !uri.host.equals("ucloud.bupt.edu.cn", ignoreCase = true) ||
                effectivePort != 443 || uri.userInfo != null
            ) {
                return null
            }
            uri.rawQuery.orEmpty().split('&').firstNotNullOfOrNull { field ->
                val name = URLDecoder.decode(field.substringBefore('='), StandardCharsets.UTF_8.name())
                if (name != "ticket" || !field.contains('=')) return@firstNotNullOfOrNull null
                URLDecoder.decode(field.substringAfter('='), StandardCharsets.UTF_8.name())
                    .takeIf(String::isNotEmpty)
            }
        }.getOrNull()

        private fun formBody(vararg fields: Pair<String, String>): String = fields.joinToString("&") {
            "${encode(it.first)}=${encode(it.second)}"
        }

        private fun encode(value: String): String =
            URLEncoder.encode(value, StandardCharsets.UTF_8.name())

        private fun decodeHTMLEntities(value: String): String = value
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&apos;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")

        private fun stringValue(value: Any?): String? = when (value) {
            null, JSONObject.NULL -> null
            is String -> value.trim().takeIf(String::isNotEmpty)
            is Number -> value.toString()
            else -> null
        }

        private fun requireUCloudDate(value: String) {
            if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) {
                throw DailyInfoClientException("作业日期格式不正确。")
            }
            runCatching {
                val parts = value.split('-').map(String::toInt)
                java.util.GregorianCalendar().apply {
                    isLenient = false
                    clear()
                    set(parts[0], parts[1] - 1, parts[2])
                    timeInMillis
                }
            }.getOrElse { throw DailyInfoClientException("作业日期格式不正确。", it) }
        }
    }
}
