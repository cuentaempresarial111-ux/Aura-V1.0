package com.ciberdefensa.aura

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.provider.Settings
import android.service.notification.NotificationListenerService

object AuraAppGenomeScanner {
    private const val ACCESSIBILITY_PERMISSION =
        "android.permission.BIND_ACCESSIBILITY_SERVICE"
    private const val NOTIFICATION_PERMISSION =
        "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"

    fun scan(context: Context): Map<String, Any> {
        val packageManager = context.packageManager
        val enabledAccessibility = if (
            Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0,
            ) == 1
        ) {
            enabledComponents(
                Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                ),
            )
        } else {
            emptySet()
        }
        val enabledNotificationListeners = enabledComponents(
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ),
        )

        val installedApps = packageManager
            .getInstalledApplications(PackageManager.GET_META_DATA)
            .associateBy { it.packageName }
        val activeServices = mutableMapOf<String, MutableList<Map<String, String>>>()

        collectActiveServices(
            packageManager = packageManager,
            action = AccessibilityService.SERVICE_INTERFACE,
            requiredPermission = ACCESSIBILITY_PERMISSION,
            enabledComponents = enabledAccessibility,
            serviceType = "ACCESSIBILITY",
            installedApplications = installedApps,
            output = activeServices,
        )
        collectActiveServices(
            packageManager = packageManager,
            action = NotificationListenerService.SERVICE_INTERFACE,
            requiredPermission = NOTIFICATION_PERMISSION,
            enabledComponents = enabledNotificationListeners,
            serviceType = "NOTIFICATION_LISTENER",
            installedApplications = installedApps,
            output = activeServices,
        )

        val applications = activeServices.entries
            .sortedBy { it.key }
            .map { (packageName, services) ->
                val appInfo = installedApps.getValue(packageName)
                mapOf(
                    "package_name" to packageName,
                    "app_name" to packageManager.getApplicationLabel(appInfo).toString(),
                    "active_services" to services,
                )
            }

        return mapOf(
            "timestamp" to System.currentTimeMillis(),
            "count" to applications.size,
            "applications" to applications,
        )
    }

    private fun enabledComponents(value: String?): Set<ComponentName> =
        value.orEmpty()
            .split(':')
            .mapNotNull { component ->
                ComponentName.unflattenFromString(component.trim())
            }
            .toSet()

    @Suppress("DEPRECATION")
    private fun collectActiveServices(
        packageManager: PackageManager,
        action: String,
        requiredPermission: String,
        enabledComponents: Set<ComponentName>,
        serviceType: String,
        installedApplications: Map<String, ApplicationInfo>,
        output: MutableMap<String, MutableList<Map<String, String>>>,
    ) {
        val intent = Intent(action)
        val matches = packageManager.queryIntentServices(
            intent,
            PackageManager.MATCH_DISABLED_COMPONENTS,
        )

        for (match in matches) {
            val serviceInfo = match.serviceInfo ?: continue
            val appInfo = installedApplications[serviceInfo.packageName] ?: continue
            val component = ComponentName(serviceInfo.packageName, serviceInfo.name)
            if (serviceInfo.permission != requiredPermission ||
                !serviceInfo.enabled ||
                !appInfo.enabled ||
                    component !in enabledComponents
            ) {
                continue
            }

            output.getOrPut(serviceInfo.packageName) { mutableListOf() }.add(
                mapOf(
                    "type" to serviceType,
                    "service_name" to serviceInfo.name,
                    "required_permission" to requiredPermission,
                ),
            )
        }
    }
}
