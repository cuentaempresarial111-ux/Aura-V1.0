package com.ciberdefensa.aura

import android.os.Build
import android.os.Debug

object AuraHostileEnvironment {
    private val emulatorFingerprintMarkers = listOf("generic", "unknown", "sdk_gphone")
    private val emulatorModelMarkers = listOf(
        "emulator",
        "android sdk built for",
        "google_sdk",
        "sdk_gphone",
    )
    private val emulatorHardwareMarkers = listOf("goldfish", "ranchu", "vbox", "qemu")

    fun inspect(): Map<String, Any> {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        val indicators = mutableListOf<String>()

        if (emulatorFingerprintMarkers.any(fingerprint::contains)) {
            indicators.add("emulator_fingerprint")
        }
        if (emulatorModelMarkers.any(model::contains)) {
            indicators.add("emulator_model")
        }
        if (emulatorHardwareMarkers.any(hardware::contains)) {
            indicators.add("emulator_hardware")
        }

        val debuggerConnected = Debug.isDebuggerConnected()
        if (debuggerConnected) indicators.add("debugger_attached")

        val hostile = indicators.isNotEmpty()
        return mapOf(
            "isEmulator" to indicators.any { it.startsWith("emulator_") },
            "isDebuggerConnected" to debuggerConnected,
            "isHostile" to hostile,
            "threatLevel" to if (hostile) "CRITICAL" else "SECURE",
            "indicators" to indicators,
            "timestamp" to System.currentTimeMillis(),
        )
    }
}
