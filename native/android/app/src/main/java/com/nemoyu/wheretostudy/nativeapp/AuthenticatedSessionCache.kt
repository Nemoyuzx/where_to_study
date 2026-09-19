package com.nemoyu.wheretostudy.nativeapp

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import org.json.JSONObject

/** Process memory only: retain one credential digest and one session, never credentials. */
internal class AuthenticatedSessionCache<T : Any>(
    private val generation: () -> Long = LocalDataCoordinator::snapshot,
    private val expiresAtMillis: (T) -> Long? = { null },
    private val clockMillis: () -> Long = System::currentTimeMillis,
) {
    internal class Lease<T>(val value: T, val revision: Long, val expiresAtMillis: Long)
    private data class Flight<T>(val result: CompletableFuture<Lease<T>>)
    private val lock = Any()
    private var owner: String? = null
    private var ownerGeneration = -1L
    private var cached: Lease<T>? = null
    private var flight: Flight<T>? = null
    private var revision = 0L

    fun clear() = synchronized(lock) {
        revision += 1
        owner = null
        cached = null
        flight?.result?.completeExceptionally(LocalDataInvalidatedException())
        flight = null
    }

    private fun acquire(key: String, expectedGeneration: Long, login: () -> T): Lease<T> {
        val selected = synchronized(lock) {
            if (generation() != expectedGeneration) throw LocalDataInvalidatedException()
            if (owner != key || ownerGeneration != expectedGeneration) {
                clear()
                owner = key
                ownerGeneration = expectedGeneration
            }
            cached?.takeIf { clockMillis() < it.expiresAtMillis }?.let { return it }
            cached = null
            flight?.let { it to false } ?: (Flight<T>(CompletableFuture()).also { flight = it } to true)
        }
        if (selected.second) {
            try {
                val value = login()
                synchronized(lock) {
                    if (flight !== selected.first || owner != key || generation() != expectedGeneration) {
                        throw LocalDataInvalidatedException()
                    }
                    val lease = Lease(value, revision, expiresAtMillis(value) ?: (clockMillis() + FALLBACK_LIFETIME_MS))
                    cached = lease
                    flight = null
                    selected.first.result.complete(lease)
                }
            } catch (error: Exception) {
                synchronized(lock) { if (flight === selected.first) flight = null }
                selected.first.result.completeExceptionally(error)
            }
        }
        return try {
            selected.first.result.get()
        } catch (error: ExecutionException) {
            throw (error.cause as? Exception ?: error)
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw error
        }
    }

    fun <R> perform(key: String, login: () -> T, expiresSession: (Exception) -> Boolean, request: (T) -> R): R {
        val expectedGeneration = generation()
        val first = acquire(key, expectedGeneration, login)
        try {
            return request(first.value).also { ensureCurrent(key, expectedGeneration, first.revision) }
        } catch (error: Exception) {
            if (!expiresSession(error)) throw error
            synchronized(lock) {
                ensureCurrent(key, expectedGeneration, first.revision)
                // A staggered failure from an older session cannot evict a new session.
                if (cached === first) cached = null
            }
        }
        val refreshed = acquire(key, expectedGeneration, login)
        return try {
            request(refreshed.value).also { ensureCurrent(key, expectedGeneration, refreshed.revision) }
        } catch (error: Exception) {
            if (expiresSession(error)) synchronized(lock) { if (cached === refreshed) cached = null }
            throw error
        }
    }

    private fun ensureCurrent(key: String, expectedGeneration: Long, expectedRevision: Long) = synchronized(lock) {
        if (owner != key || revision != expectedRevision || ownerGeneration != expectedGeneration || generation() != expectedGeneration) {
            throw LocalDataInvalidatedException()
        }
    }

    companion object { const val FALLBACK_LIFETIME_MS = 20 * 60 * 1_000L }
}

internal fun sessionCredentialKey(account: String, password: String): String {
    val normalized = account.trim()
    val bytes = "${normalized.length}:$normalized$password".toByteArray(StandardCharsets.UTF_8)
    return try {
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 0xff) }
    } finally { bytes.fill(0) }
}

internal object AcademicSessions {
    val cache = AuthenticatedSessionCache<String>(expiresAtMillis = SessionExpiryMessage::jwtExpiresAtMillis)
}

internal object SessionExpiryMessage {
    fun jwtExpiresAtMillis(token: String): Long? = runCatching {
        val payload = token.split('.').takeIf { it.size == 3 }?.get(1)
            ?.takeIf { it.length <= 16_384 } ?: return null
        val json = String(android.util.Base64.decode(payload, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP), StandardCharsets.UTF_8)
        expirationMillis(JSONObject(json).opt("exp"))
    }.getOrNull()

    fun expirationMillis(seconds: Any?): Long? = seconds?.toString()?.toDoubleOrNull()
        ?.takeIf { it.isFinite() && it >= 0 && it <= Long.MAX_VALUE / 1_000.0 }
        ?.let { (it * 1_000).toLong() }

    private val pattern = Regex(
        "(?:token|session|access[ _-]?token)\\s+(?:has\\s+)?(?:expired|invalid)|" +
            "(?:expired|invalid)\\s+(?:access[ _-]?)?(?:token|session)|" +
            "(?:登录|登陆|会话|令牌|认证).{0,8}(?:失效|过期|超时)|未登录|请重新登录",
        RegexOption.IGNORE_CASE,
    )
    fun matches(message: String): Boolean = pattern.containsMatchIn(message)
}
