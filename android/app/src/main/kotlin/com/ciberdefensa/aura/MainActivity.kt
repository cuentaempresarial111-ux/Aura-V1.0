package com.ciberdefensa.aura

import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.net.VpnService
import android.net.Uri
import android.os.Build
import android.os.Debug
import android.provider.Settings
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import hev.htproxy.TProxyService
import java.util.concurrent.Executors
import java.util.Locale

object AuraAntiTampering {
    private const val ANDROIDX_MASTER_KEY_ALIAS = "_androidx_security_master_key_"
    private const val FLUTTER_SECURE_STORAGE_KEY_SUFFIX =
        ".FlutterSecureStoragePluginKey"

    fun inspect(context: Context): Map<String, Any> {
        val allowedCertificates = BuildConfig.AURA_ALLOWED_CERT_SHA256
            .split(',')
            .map { it.trim().replace(":", "").uppercase() }
            .filter { it.matches(Regex("[0-9A-F]{64}")) }
            .toSet()

        val installedCertificates = installedSignerDigests(context)
        val localDebugFallback = BuildConfig.DEBUG && allowedCertificates.isEmpty()
        val signatureValid = localDebugFallback ||
            (allowedCertificates.isNotEmpty() &&
                installedCertificates.isNotEmpty() &&
                installedCertificates.all { it in allowedCertificates })

        val mapsResult = try {
            val maps = File("/proc/self/maps").bufferedReader().use { it.readText() }
                .lowercase()
            true to ("frida" in maps || "gadget" in maps)
        } catch (_: Exception) {
            false to false
        }
        val mapsInspectionSucceeded = mapsResult.first
        val fridaDetected = mapsResult.second

        val debuggerConnected = Debug.isDebuggerConnected() || Debug.waitingForDebugger()
        val debuggerBlocked = debuggerConnected && !BuildConfig.DEBUG
        val adbEnabled = try {
            Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.ADB_ENABLED,
                0,
            ) == 1
        } catch (_: Exception) {
            true
        }
        val adbBlocked = adbEnabled && !BuildConfig.DEBUG
        val integrityFailed = !signatureValid || !mapsInspectionSucceeded ||
            fridaDetected || debuggerBlocked || adbBlocked

        return mapOf(
            "isSecure" to !integrityFailed,
            "signatureValid" to signatureValid,
            "signingCertificates" to installedCertificates.toList(),
            "fridaDetected" to fridaDetected,
            "mapsInspectionSucceeded" to mapsInspectionSucceeded,
            "isDebuggerConnected" to debuggerConnected,
            "debuggerBlocked" to debuggerBlocked,
            "adbEnabled" to adbEnabled,
            "adbBlocked" to adbBlocked,
            "localDebugFallback" to localDebugFallback,
        )
    }

    fun enforce(context: Context): Map<String, Any> {
        val report = try {
            inspect(context)
        } catch (exception: Exception) {
            android.util.Log.e("AuraIntegrity", "Integrity inspection failed.", exception)
            mapOf(
                "isSecure" to false,
                "inspectionFailed" to true,
            )
        }
        if (report["isSecure"] != true) {
            destroyLocalKeystoreKeys(context)
            android.util.Log.e("AuraIntegrity", "Integrity check failed; terminating process.")
            System.exit(0)
        }
        return report
    }

    private fun installedSignerDigests(context: Context): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val packageInfo = context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            packageInfo.signingInfo?.apkContentsSigners?.map { it.toByteArray() }
                .orEmpty()
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNATURES,
            ).signatures?.map { it.toByteArray() }.orEmpty()
        }

        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.map { signature ->
            digest.digest(signature).joinToString("") { byte -> "%02X".format(byte) }
        }.toSet()
    }

    private fun destroyLocalKeystoreKeys(context: Context) {
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)
            val knownAliases = setOf(
                ANDROIDX_MASTER_KEY_ALIAS,
                context.packageName + FLUTTER_SECURE_STORAGE_KEY_SUFFIX,
            )
            knownAliases.forEach { alias ->
                if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
            }

            val aliases = keyStore.aliases()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                if (alias.startsWith("aura_")) keyStore.deleteEntry(alias)
            }
        } catch (exception: Exception) {
            android.util.Log.e("AuraIntegrity", "Could not wipe Aura Keystore keys.", exception)
        }
    }
}

class MainActivity: FlutterActivity() {
    private companion object {
        const val VPN_PERMISSION_REQUEST = 1081
        const val VOICE_REQUEST = 1082
        const val VOICE_PERMISSION_REQUEST = 1083
        const val NOTIFICATION_PERMISSION_REQUEST = 1084
    }

    private val SHIELD_CHANNEL = "com.ciberdefensa.aura/shield"
    private val TELEMETRY_CHANNEL = "com.ciberdefensa.aura/telemetry"
    private val ANTI_TAMPERING_CHANNEL = "com.ciberdefensa.aura/anti_tampering"
    private val SECURITY_CHANNEL = "com.ciberdefensa.aura/security"
    private val ENGINE_CHANNEL = "com.aura.cyberdefense/engine"
    private val VOICE_CHANNEL = "com.ciberdefensa.aura/voice"
    private val NETWORK_STREAM_CHANNEL = "com.aura.cyberdefense/network_stream"
    private val genomeScannerExecutor = Executors.newSingleThreadExecutor()
    private var pendingShieldResult: MethodChannel.Result? = null
        private var pendingVoiceResult: MethodChannel.Result? = null
    private var vpnReceiverRegistered = false
    private val vpnStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val started = intent?.getBooleanExtra("started", false) ?: false
            val message = intent?.getStringExtra("message") ?: "Sin respuesta del servicio VPN."
            pendingShieldResult?.success(started)
            pendingShieldResult = null
            if (!started) android.util.Log.e("AuraVPN", message)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerVpnReceiver()
        AuraNetworkStream.setApplicationContext(applicationContext)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NETWORK_STREAM_CHANNEL,
        ).setStreamHandler(AuraNetworkStream)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ENGINE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTunnelStats" -> {
                    if (!TProxyService.TProxyIsRunning()) {
                        result.success(longArrayOf(0, 0, 0, 0))
                    } else {
                        try {
                            result.success(TProxyService.TProxyGetStats())
                        } catch (_: Exception) {
                            result.error("TUN_STATS", "No se pudieron leer las métricas TUN.", null)
                        }
                    }
                }

                "addDnsBlockRule" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val domain = normalizeThreatDomain(arguments?.get("domain") as? String)
                    if (domain == null) {
                        result.success(false)
                    } else if (!TProxyService.TProxyIsRunning()) {
                        result.success(false)
                    } else {
                        try {
                            val blocked = TProxyService.TProxyBlockDomain(domain)
                            result.success(blocked)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }

                "openAppDetails" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val targetPackage = arguments?.get("package_name") as? String
                    val reason = arguments?.get("reason") as? String
                    if (targetPackage.isNullOrBlank()) {
                        result.success(mapOf("ok" to false, "error" to "Paquete no válido."))
                    } else {
                        try {
                            packageManager.getApplicationInfo(targetPackage, 0)
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", targetPackage, null),
                                ),
                            )
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "package_name" to targetPackage,
                                    "reason" to reason?.take(240),
                                    "user_action_required" to true,
                                    "message" to "Panel de la aplicación abierto; la decisión corresponde al usuario.",
                                ),
                            )
                        } catch (exception: ActivityNotFoundException) {
                            result.success(mapOf("ok" to false, "error" to "No se pudo abrir Ajustes."))
                        } catch (exception: Exception) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to exception.message ?: "No se pudo abrir el panel de la app.",
                                ),
                            )
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> startVoiceRecognition(result)
                else -> result.notImplemented()
            }
        }

        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkHostileEnvironment" -> {
                    result.success(AuraHostileEnvironment.inspect())
                }

                "scanActiveSensitiveServices" -> {
                    genomeScannerExecutor.execute {
                        try {
                            val scanResult = AuraAppGenomeScanner.scan(applicationContext)
                            runOnUiThread { result.success(scanResult) }
                        } catch (exception: Exception) {
                            runOnUiThread {
                                result.error(
                                    "APP_GENOME_SCAN_FAILED",
                                    exception.message ?: "No se pudo completar el escaneo.",
                                    null,
                                )
                            }
                        }
                    }
                }

                "mitigateNetworkThreat" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val appPackage = arguments?.get("app_package") as? String
                    val domain = normalizeThreatDomain(
                        arguments?.get("domain") as? String,
                    )
                    if (appPackage.isNullOrBlank() || domain == null) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "error" to "Se requiere un paquete y un dominio válidos.",
                            ),
                        )
                    } else {
                        try {
                            val appPackageVerified = try {
                                packageManager.getApplicationInfo(appPackage, 0)
                                true
                            } catch (_: Exception) {
                                false
                            }
                            if (!TProxyService.TProxyIsRunning()) {
                                result.success(
                                    mapOf(
                                        "ok" to false,
                                        "error" to "El túnel Aura no está activo.",
                                        "enforcement_scope" to "device-wide",
                                    ),
                                )
                            } else {
                                val blocked = TProxyService.TProxyBlockDomain(domain)
                                result.success(
                                    mapOf(
                                        "ok" to blocked,
                                        "domain" to domain,
                                        "requested_app_package" to appPackage,
                                        "app_package_verified" to appPackageVerified,
                                        "enforcement_scope" to "device-wide",
                                        "app_specific" to false,
                                        "message" to if (blocked) {
                                            "Dominio bloqueado globalmente en el DNS local."
                                        } else {
                                            "El motor no aceptó la regla de dominio."
                                        },
                                    ),
                                )
                            }
                        } catch (exception: Exception) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to exception.message
                                        ?: "No se pudo aplicar la regla DNS.",
                                    "enforcement_scope" to "device-wide",
                                ),
                            )
                        }
                    }
                }

                "isolateMaliciousApp" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val targetPackage = arguments?.get("package_name") as? String
                    val reason = arguments?.get("reason") as? String
                    if (targetPackage.isNullOrBlank() || reason.isNullOrBlank()) {
                        result.success(
                            mapOf("ok" to false, "error" to "Paquete o motivo vacío."),
                        )
                    } else {
                        try {
                            packageManager.getApplicationInfo(targetPackage, 0)
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", targetPackage, null),
                                ),
                            )
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "package_name" to targetPackage,
                                    "reason" to reason.take(240),
                                    "user_action_required" to true,
                                    "message" to "Panel de la aplicación abierto; la decisión corresponde al usuario.",
                                ),
                            )
                        } catch (exception: ActivityNotFoundException) {
                            result.success(
                                mapOf("ok" to false, "error" to "No se pudo abrir Ajustes."),
                            )
                        } catch (exception: Exception) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to exception.message
                                        ?: "No se pudo abrir el panel de la app.",
                                ),
                            )
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TELEMETRY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "captureRiskTelemetry" -> {
                    val appRiskList = mutableListOf<Map<String, Any>>()
                    val pm = packageManager
                    val installedPackages = pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
                    val permisosCriticos = listOf(
                        "android.permission.READ_SMS",
                        "android.permission.RECEIVE_SMS",
                        "android.permission.RECORD_AUDIO",
                        "android.permission.CAMERA",
                        "android.permission.ACCESS_FINE_LOCATION",
                    )

                    for (pkg in installedPackages) {
                        val applicationInfo = pkg.applicationInfo ?: continue
                        if ((applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) == 0) {
                            val permisosSolicitados = pkg.requestedPermissions
                            if (permisosSolicitados != null) {
                                val coincidenciasRiesgo = mutableListOf<String>()
                                for (permiso in permisosSolicitados) {
                                    if (permisosCriticos.contains(permiso)) {
                                        coincidenciasRiesgo.add(permiso)
                                    }
                                }

                                if (coincidenciasRiesgo.isNotEmpty()) {
                                    val datosApp = mapOf(
                                        "name" to applicationInfo.loadLabel(pm).toString(),
                                        "package" to pkg.packageName,
                                        "target_sdk" to applicationInfo.targetSdkVersion,
                                        "risk_permissions" to coincidenciasRiesgo,
                                    )
                                    appRiskList.add(datosApp)
                                }
                            }
                        }
                    }

                    result.success(appRiskList)
                }

                "checkAppIntegrity" -> {
                    val isDebugActive =
                        Debug.isDebuggerConnected() || Debug.waitingForDebugger()
                    val dataPath = applicationContext.filesDir.absolutePath.lowercase()
                    val isCloned = dataPath.contains("virtual") ||
                        dataPath.contains("parallel") ||
                        dataPath.contains("dual") ||
                        dataPath.contains("multiple")
                    val integrityReport = mapOf(
                        "isDebuggerConnected" to isDebugActive,
                        "isVirtualEnvironment" to isCloned,
                        "isSecure" to (!isDebugActive && !isCloned),
                    )
                    result.success(integrityReport)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANTI_TAMPERING_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkIntegrity" -> result.success(AuraAntiTampering.inspect(this))
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHIELD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startShield" -> {
                    requestShieldStart(result)
                }

                "stopShield" -> {
                    val intent = Intent(this, AuraVpnService::class.java)
                    stopService(intent)
                    result.success(true)
                }

                "getLatestBlockedIps" -> {
                    val blockedIps = listOf<String>()
                    result.success(blockedIps)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            VPN_PERMISSION_REQUEST -> {
                if (resultCode == RESULT_OK) {
                    startVpnService()
                } else {
                    pendingShieldResult?.success(false)
                    pendingShieldResult = null
                }
            }

            VOICE_REQUEST -> {
                val transcript = if (resultCode == RESULT_OK) {
                    data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                        ?.firstOrNull()
                } else {
                    null
                }
                pendingVoiceResult?.success(transcript)
                pendingVoiceResult = null
            }
        }
    }

    @Deprecated("Deprecated by Android; retained for minSdk 24 runtime permissions.")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == VOICE_PERMISSION_REQUEST) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                launchVoiceRecognition()
            } else {
                pendingVoiceResult?.error(
                    "MICROPHONE_PERMISSION_DENIED",
                    "Se necesita permiso de micrófono para dictar comandos.",
                    null,
                )
                pendingVoiceResult = null
            }
        }
    }

    private fun startVoiceRecognition(result: MethodChannel.Result) {
        if (pendingVoiceResult != null) {
            result.error("VOICE_BUSY", "Ya hay un reconocimiento en curso.", null)
            return
        }
        pendingVoiceResult = result
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                VOICE_PERMISSION_REQUEST,
            )
        } else {
            launchVoiceRecognition()
        }
    }

    private fun launchVoiceRecognition() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-ES")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "es-ES")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Habla con Aura")
        }
        try {
            startActivityForResult(intent, VOICE_REQUEST)
        } catch (exception: ActivityNotFoundException) {
            pendingVoiceResult?.error(
                "VOICE_RECOGNIZER_UNAVAILABLE",
                "No hay un reconocedor de voz instalado.",
                null,
            )
            pendingVoiceResult = null
        }
    }

    private fun requestShieldStart(result: MethodChannel.Result) {
        if (pendingShieldResult != null) {
            result.error("VPN_BUSY", "Ya hay una solicitud VPN pendiente.", null)
            return
        }

        pendingShieldResult = result
        val consentIntent = VpnService.prepare(this)
        if (consentIntent != null) {
            startActivityForResult(consentIntent, VPN_PERMISSION_REQUEST)
        } else {
            startVpnService()
        }
    }

    private fun startVpnService() {
        try {
            val intent = Intent(this, AuraVpnService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (exception: Exception) {
            pendingShieldResult?.success(false)
            pendingShieldResult = null
            android.util.Log.e("AuraVPN", "No se pudo iniciar AuraVpnService.", exception)
        }
    }

    private fun registerVpnReceiver() {
        if (vpnReceiverRegistered) return
        val filter = IntentFilter(AuraVpnService.ACTION_STATE)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(vpnStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(vpnStateReceiver, filter)
        }
        vpnReceiverRegistered = true
    }

    override fun onDestroy() {
        genomeScannerExecutor.shutdownNow()
        if (vpnReceiverRegistered) {
            unregisterReceiver(vpnStateReceiver)
            vpnReceiverRegistered = false
        }
        pendingShieldResult?.success(false)
        pendingShieldResult = null
        pendingVoiceResult?.error("ACTIVITY_DESTROYED", "Activity cerrada.", null)
        pendingVoiceResult = null
        super.onDestroy()
    }

    private fun normalizeThreatDomain(value: String?): String? {
        val domain = value?.trim()?.trimEnd('.')?.lowercase(Locale.ROOT) ?: return null
        if (domain.isEmpty() || domain.length > 253) return null
        val labelPattern = Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")
        return domain.split('.').takeIf { labels ->
            labels.all { it.length <= 63 && labelPattern.matches(it) }
        }?.joinToString(".")
    }
}
