package com.ciberdefensa.aura

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.OsConstants
import io.flutter.plugin.common.EventChannel
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.ArrayDeque
import java.util.concurrent.Executors

private data class PendingDnsEvent(
    val timestamp: Long,
    val domain: String,
    val action: String,
    val sourceAddress: String,
    val sourcePort: Int,
)

object AuraNetworkStream : EventChannel.StreamHandler {
    private const val MAX_PENDING_EVENTS = 512
    private const val DNS_SINKHOLE_ADDRESS = "10.0.0.3"

    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val uidResolver = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "AuraDnsUidResolver").apply { isDaemon = true }
    }
    private val pendingDnsEvents = ArrayDeque<PendingDnsEvent>()
    private val pendingEvents = ArrayDeque<Map<String, Any>>()
    private var applicationContext: Context? = null
    private var eventSink: EventChannel.EventSink? = null
    private var drainScheduled = false
    private var resolverScheduled = false

    fun setApplicationContext(context: Context) {
        applicationContext = context.applicationContext
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        synchronized(lock) {
            eventSink = events
            scheduleDrainLocked()
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) {
            eventSink = null
            pendingDnsEvents.clear()
            pendingEvents.clear()
            drainScheduled = false
        }
    }

    fun emitDnsEvent(
        domain: String,
        actionCode: Int,
        sourceAddress: String,
        sourcePort: Int,
    ) {
        val action = when (actionCode) {
            2 -> "DGA_ALERT"
            1 -> "BLOCKED"
            else -> "ALLOWED"
        }
        synchronized(lock) {
            if (pendingDnsEvents.size == MAX_PENDING_EVENTS) pendingDnsEvents.removeFirst()
            pendingDnsEvents.addLast(
                PendingDnsEvent(
                    System.currentTimeMillis(), domain, action, sourceAddress, sourcePort,
                ),
            )
            if (!resolverScheduled) {
                resolverScheduled = true
                uidResolver.execute(::resolveQueuedEvents)
            }
        }
    }

    private fun resolveQueuedEvents() {
        while (true) {
            val pending = synchronized(lock) {
                if (pendingDnsEvents.isEmpty()) {
                    resolverScheduled = false
                    null
                } else {
                    pendingDnsEvents.removeFirst()
                }
            } ?: return

            val event = mapOf(
                "timestamp" to pending.timestamp,
                "source_app" to resolveSourceApp(pending.sourceAddress, pending.sourcePort),
                "requested_domain" to pending.domain,
                "action" to pending.action,
            )
            AuraVpnService.recordDnsAuditEvent(event)
            synchronized(lock) {
                if (pendingEvents.size == MAX_PENDING_EVENTS) pendingEvents.removeFirst()
                pendingEvents.addLast(event)
                scheduleDrainLocked()
            }
        }
    }

    private fun resolveSourceApp(sourceAddress: String, sourcePort: Int): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || sourcePort !in 1..65535) {
            return "uid-unavailable"
        }

        val context = applicationContext ?: return "uid-unavailable"
        return try {
            val connectivity =
                context.getSystemService(ConnectivityManager::class.java)
                    ?: return "uid-unavailable"
            val local = InetSocketAddress(InetAddress.getByName(sourceAddress), sourcePort)
            val remote = InetSocketAddress(InetAddress.getByName(DNS_SINKHOLE_ADDRESS), 53)
            val uid = connectivity.getConnectionOwnerUid(OsConstants.IPPROTO_UDP, local, remote)
            if (uid < 0) return "uid-unavailable"
            context.packageManager.getPackagesForUid(uid)
                ?.takeIf { it.isNotEmpty() }
                ?.joinToString(",")
                ?: "uid:$uid"
        } catch (_: SecurityException) {
            "uid-unavailable"
        } catch (_: Exception) {
            "uid-unavailable"
        }
    }

    private fun scheduleDrainLocked() {
        if (drainScheduled || eventSink == null || pendingEvents.isEmpty()) return
        drainScheduled = true
        mainHandler.post(::drainOne)
    }

    private fun drainOne() {
        val sink: EventChannel.EventSink?
        val event: Map<String, Any>?
        synchronized(lock) {
            sink = eventSink
            event = if (sink == null) null else pendingEvents.pollFirst()
            if (event == null) {
                drainScheduled = false
                return
            }
        }

        try {
            sink?.success(event)
        } finally {
            synchronized(lock) {
                drainScheduled = false
                scheduleDrainLocked()
            }
        }
    }
}