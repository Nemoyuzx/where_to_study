package com.nemoyu.wheretostudy.nativeapp

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.io.EOFException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLException

/** No network request or WebView initialization happens at application startup. */
class NativeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CellularAssist.initialize(this)
    }
}

internal object CellularAssistPolicy {
    const val preferenceKey = "cellular_assist_enabled"
    fun canRetry(method: String, enabled: Boolean, wifi: Boolean, error: Throwable): Boolean {
        if (!enabled || !wifi || method !in setOf("GET", "HEAD")) return false
        var current: Throwable? = error
        var connectionFailure = false
        repeat(8) {
            val cause = current ?: return connectionFailure
            if (cause is SSLException || cause is InterruptedException || cause is CancellationException ||
                (cause is InterruptedIOException && cause !is SocketTimeoutException)) return false
            connectionFailure = connectionFailure || cause is UnknownHostException || cause is ConnectException ||
                cause is NoRouteToHostException || cause is SocketTimeoutException || cause is SocketException ||
                cause is EOFException
            current = cause.cause?.takeUnless { it === cause }
        }
        return connectionFailure
    }
}

/** Request-scoped route only: never binds the process or replays credential POSTs.
 * The original URL policy, TLS trust, request headers, response caps and stream
 * cleanup remain owned by each existing transport. No Activity is retained.
 */
internal object CellularAssist {
    private var appContext: Context? = null
    @Volatile private var blockedForSession = false
    private val route = ThreadLocal<Network>()
    private val leases = Semaphore(4)

    fun initialize(context: Context) { appContext = context.applicationContext }
    val sessionPermitsFallback: Boolean get() = !blockedForSession
    fun blockUntilPreferenceSaved() { blockedForSession = true }
    fun preferenceSaved() { blockedForSession = false }

    fun openConnection(url: URL): HttpURLConnection =
        (route.get()?.openConnection(url) ?: url.openConnection()) as HttpURLConnection

    fun <T> readOnly(method: String = "GET", operation: () -> T): T {
        if (route.get() != null) return operation()
        val context = appContext ?: return operation()
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return operation()
        val prefs = AppPreferences(context)
        val enabled = prefs.cellularAssistEnabled
        val wifi = enabled && runCatching {
            manager.getNetworkCapabilities(manager.activeNetwork)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }.getOrDefault(false)
        try { return operation() } catch (original: Exception) {
            if (Thread.currentThread().isInterrupted ||
                !CellularAssistPolicy.canRetry(method, enabled, wifi, original) ||
                !prefs.cellularAssistEnabled || !leases.tryAcquire()) throw original
            try {
                return onCellular(manager, original, operation)
            } finally { leases.release() }
        }
    }

    private fun <T> onCellular(manager: ConnectivityManager, original: Exception, operation: () -> T): T {
        val ready = CountDownLatch(1)
        val candidate = AtomicReference<Network?>()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { candidate.compareAndSet(null, network); ready.countDown() }
            override fun onUnavailable() { ready.countDown() }
            override fun onLost(network: Network) { candidate.compareAndSet(network, null) }
        }
        var registered = false
        try {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
            try {
                manager.requestNetwork(request, callback)
                registered = true
            } catch (_: RuntimeException) { throw original }
            // Also bounds API 24/25 callbacks, without a long-lived executor/timer.
            if (!ready.await(3, TimeUnit.SECONDS)) throw original
            // A user may disable the feature while waiting for the SIM route.
            if (!sessionPermitsFallback || appContext?.let { AppPreferences(it).cellularAssistEnabled } != true) throw original
            val network = candidate.get() ?: throw original
            route.set(network)
            return operation() // exactly one fallback, including bounded stream reads
        } catch (interrupted: InterruptedException) {
            Thread.currentThread().interrupt()
            throw interrupted
        } finally {
            route.remove()
            if (registered) runCatching { manager.unregisterNetworkCallback(callback) }
        }
    }
}
