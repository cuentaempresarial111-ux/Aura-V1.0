# Aura Cyberdefense V1.0: Descripción oficial de la solución agéntica inteligente para Android sin privilegios root

Aura Cyberdefense es una aplicación agéntica de ciberdefensa para Android, construida con Flutter, Dart y un motor de túnel nativo C. Opera sin privilegios root mediante `VpnService`; Android requiere autorización explícita del usuario para iniciar el túnel. La aplicación combina auditoría DNS local, telemetría de red, análisis de amenazas con Gemini, controles defensivos nativos y una interfaz accesible por voz.

Gemini necesita conectividad y una API key configurada por el usuario. La clave se conserva localmente mediante `flutter_secure_storage`; no se incluye en el código ni en el pipeline de Codemagic.

## Arquitectura de Ciberdefensa Avanzada

### Flujo de telemetría y análisis

El camino de eventos y contramedidas está conectado de extremo a extremo:

1. **TUN y motor C:** Android entrega el descriptor TUN a `hev-socks5-tunnel`. Su loop de lectura examina paquetes antes de entregarlos a lwIP. `hev-mapped-dns` procesa las consultas UDP/53, reconoce dominios incluidos en la lista de bloqueo y aplica una heurística DGA local.
2. **C y JNI:** el motor informa el dominio, la acción y el origen mediante `hev_jni_report_dns_event`. JNI adjunta el hilo nativo a la JVM cuando es necesario y llama a `TProxyService.dispatchDnsEvent`.
3. **Kotlin y EventChannel:** `AuraNetworkStream` conserva el código de acción (`ALLOWED`, `BLOCKED` o `DGA_ALERT`), resuelve la aplicación de origen fuera del hilo del túnel cuando Android lo permite y publica el mapa de evento en `com.aura.cyberdefense/network_stream`.
4. **Auditor Dart:** `AuraNetworkAuditor` valida el evento, lo incorpora a su búfer acotado, persiste registros por lotes y, ante `BLOCKED` o `DGA_ALERT`, envía inmediatamente el JSON del evento a `AuraAIBrain.analyzeThreatPayload`.
5. **Gemini Function Calling:** `AuraAIBrain` usa `google_generative_ai` y `gemini-2.5-flash`. Las declaraciones de función disponibles incluyen `mitigate_network_threat` y `isolate_malicious_app`. El procesamiento remoto es asíncrono, como exige una llamada de red.
6. **Contramedida Kotlin/C:** si Gemini solicita mitigar un dominio, el callback del auditor invoca `addDnsBlockRule` por `MethodChannel`. `MainActivity` valida el dominio y llama a `TProxyService.TProxyBlockDomain`; JNI llega a la lista compartida de `hev-mapped-dns`, protegida por mutex. El resultado booleano vuelve a Dart y Gemini recibe la respuesta real de la herramienta. La regla es global para el dispositivo.

`isolate_malicious_app` abre los ajustes Android de la aplicación indicada. No fuerza detención ni desinstalación: esas acciones requieren decisión del usuario o privilegios que una aplicación VPN ordinaria no posee.

### Canales de plataforma

| Canal | Dirección y responsabilidad |
|---|---|
| `com.aura.cyberdefense/network_stream` | Kotlin publica eventos de auditoría mediante `EventChannel`. |
| `com.aura.cyberdefense/engine` | Dart solicita `addDnsBlockRule` u `openAppDetails`; Kotlin responde con el resultado de la operación. |
| `com.ciberdefensa.aura/shield` | Dart solicita el inicio/parada del servicio VPN y Android gestiona el consentimiento del sistema. |
| `com.ciberdefensa.aura/telemetry` | Dart solicita inventario de permisos de riesgo al código Android. |

## Gestión de Estado Reactivo y Avatar Emocional

`AuraStateProvider`, basado en `ChangeNotifier` y `provider` (`^6.1.2`), es la fuente de estado compartido de la aplicación. Expone el nivel de seguridad, el estado VPN, el escaneo, la actividad de consulta/voz, los registros de presentación y hasta 500 eventos de telemetría. La interfaz consume los cambios con `context.watch<AuraStateProvider>()`; `main.dart` no utiliza `setState`.

| Nivel | Estado visual del avatar | Comportamiento |
|---|---|---|
| `safe` | `idle_friendly`, azul | Estado normal. |
| `warning` | `scanning_active`, naranja | Evento DNS `BLOCKED` o detección `DGA_ALERT` pendiente de evaluación. |
| `critical` | `threat_mitigation_mode`, rojo | Gemini inicia una contramedida o el motor confirma una condición crítica. El provider notifica a la UI y solicita una alerta hablada en español mediante `flutter_tts`. |

El provider notifica a sus oyentes al cambiar el estado y mantiene un máximo de 500 eventos en memoria. El `CustomPainter` usa el estado emocional para representar alerta y escaneo en el avatar.

## Mitigación de Red de Élite (Zero Point Blind)

El motor C descarta en el loop propietario del descriptor TUN los paquetes TCP/UDP con destino al puerto 853 (DoT). También descarta tráfico TCP/UDP al puerto 443 dirigido a estos resolvedores IPv4 conocidos: Cloudflare `1.1.1.1` y `1.0.0.1`, Google `8.8.8.8` y `8.8.4.4`, y Quad9 `9.9.9.9`. Los descartes DoH/DoT se notifican como `BLOCKED` con el dominio descriptivo `DoH/DoT Bypass Attempt`.

Este control **bloquea** esos flujos; no descifra ni convierte una conexión DoH/DoT en una consulta UDP/53. Un downgrade transparente no es posible sin terminar el protocolo cifrado y cambiar el comportamiento de la aplicación cliente. Una app puede fallar o recurrir a otro resolvedor. La regla DoH se limita a las direcciones IPv4 enumeradas; no constituye bloqueo universal de todos los proveedores DoH, direcciones IPv6, DoQ ni resolvedores personalizados.

La bóveda anterior basada en XOR y archivos temporales fue eliminada. `AuraSecureVault` usa exclusivamente `flutter_secure_storage` (`^9.2.4`), activa `encryptedSharedPreferences` y `resetOnError` en Android, guarda la API key y mantiene el historial como JSON limitado a 500 registros. El cifrado usa los mecanismos disponibles en el dispositivo; el respaldo hardware del Keystore no puede garantizarse desde la aplicación para todos los modelos.

La heurística DGA analiza nombres observados en DNS local. Es un indicador estructural, no un servicio de reputación, una prueba de malware ni una garantía de detección. La atribución de UID depende de las API y permisos disponibles; puede registrarse como `uid-unavailable`.

## Dependencias principales

Las restricciones directas declaradas en `pubspec.yaml` son:

| Paquete | Restricción | Función |
|---|---:|---|
| `provider` | `^6.1.2` | Estado reactivo de VPN, telemetría, presentación y avatar. |
| `google_generative_ai` | `^0.4.7` | Gemini Function Calling asíncrono. |
| `flutter_secure_storage` | `^9.2.4` | Almacenamiento local cifrado de clave y registros. |
| `flutter_tts` | `^4.2.5` | Alertas y respuestas habladas en español. |

El proyecto requiere Dart `>=3.0.0 <4.0.0` y usa Flutter del SDK. `pubspec.lock` determina las versiones resueltas; después de eliminarlo, `flutter pub get` volverá a resolver las restricciones y generará un lockfile nuevo.

## Pipelines de Integración Continua

El workflow `android-build` de [`codemagic.yaml`](codemagic.yaml) está configurado para Flutter `3.47.5`, Java `21` y Android release. Para cada `push` en `main` o `principal`, configura `android/local.properties`, ejecuta `flutter clean`, `flutter pub get` y `flutter build apk --release`. El modelo se selecciona con `GEMINI_MODEL` y el valor predeterminado es `gemini-2.5-flash`.

La integración C se construye directamente con el NDK de Flutter mediante `android/app/build.gradle`, `Android.mk` y la tarea Gradle `buildHevSocks5Tunnel`, dependiente de `preBuild`. No requiere un paso manual separado en Codemagic. El flujo publica los APK de `build/app/outputs/flutter-apk/`.

### Saneamiento local de dependencias

El siguiente comando limpia los artefactos Flutter del proyecto, elimina la caché global de paquetes Pub indicada por `PUB_CACHE` (o `~/.pub-cache`), borra el lockfile local, vuelve a descargar y resolver dependencias y analiza el proyecto. Es destructivo para la caché de paquetes compartida, pero no elimina el SDK Flutter:

```bash
pub_cache="${PUB_CACHE:-$HOME/.pub-cache}" && [[ -n "$pub_cache" && "$pub_cache" != "/" && "$pub_cache" != "$HOME" ]] && flutter clean && rm -rf -- "$pub_cache" && rm -f pubspec.lock && flutter pub get && flutter analyze
```

## Compilación local

```bash
flutter pub get
flutter build apk --release \
  --dart-define="GEMINI_MODEL=${GEMINI_MODEL:-gemini-2.5-flash}"
```

El APK se genera en `build/app/outputs/flutter-apk/`. El modelo no es la API key; configura la clave desde la aplicación y evita almacenarla en el repositorio o en logs de CI.