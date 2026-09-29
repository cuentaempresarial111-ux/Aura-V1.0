# Aura Cyberdefense (V1.0)

![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter)
![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0.0-0175C2?logo=dart)
![Build](https://img.shields.io/badge/Build-Codemagic-2F80ED)
![Rootless](https://img.shields.io/badge/Operation-Without%20root-198754)

Aura Cyberdefense es un asistente de ciberdefensa proactiva y privacidad para dispositivos Android, desarrollado en Flutter e integrado con Gemini. Reúne consultas de seguridad, comprobaciones de integridad, telemetría Android, síntesis de voz y un escudo de red basado en el servicio VPN nativo de Android.

La aplicación está diseñada para operar sin acceso root. El escudo VPN requiere autorización explícita del usuario y las capacidades de integridad y telemetría dependen de los canales nativos disponibles en Android. La IA requiere conectividad y una clave de Gemini configurada.

---

## ✨ Características principales

- **Cerebro de IA integrado:** conecta con Gemini, usando `gemini-2.5-flash` de forma predeterminada, para responder consultas y analizar hallazgos. El servicio auxiliar empaqueta la telemetría como JSON; la pantalla principal también puede enviar consultas de texto y procesar llamadas a herramientas.
- **Bóveda local:** persiste la clave de Gemini y hasta 500 registros con `flutter_secure_storage`. En Android se habilita `encryptedSharedPreferences`; el proyecto no especifica ni garantiza explícitamente que el cifrado esté respaldado por hardware.
- **Auditoría de conectividad:** incluye una utilidad que publica cambios del estado del escudo mediante un `Stream` y comprueba la resolución DNS de `cloudflare.com` bajo demanda. No es una inspección continua del tráfico de red.
- **Comprobación de integridad:** combina resultados de canales nativos Android con comprobaciones locales de indicadores como binarios `su`, depuración, entorno virtual y manipulación.
- **Interfaz de voz:** lee respuestas y alertas en español mediante `flutter_tts`.
- **Radar animado:** representa visualmente el estado de escaneo con un componente `CustomPainter`.
- **Escudo VPN:** permite solicitar el inicio o la detención del servicio VPN nativo de Android, con consentimiento del usuario.

---

## 🧩 Estructura de `lib/`

| Archivo | Responsabilidad |
|---|---|
| [`main.dart`](lib/main.dart) | Punto de entrada Flutter. Configura el tema oscuro, muestra `AuraCoreScreen` y coordina el monitor de integridad, el asistente, voz, bóveda, escaneo y escudo desde la interfaz principal. |
| [`ai_brain.dart`](lib/ai_brain.dart) | Integración principal con Gemini. Gestiona la clave, prepara el modelo y las herramientas, procesa llamadas a funciones y usa `MethodChannel` para solicitar telemetría y controlar el escudo. |
| [`security_engine.dart`](lib/security_engine.dart) | Consulta comprobaciones de integridad a los canales nativos, busca determinados binarios `su` y emite un stream periódico de estado, cada cinco segundos de forma predeterminada. |
| [`secure_vault.dart`](lib/secure_vault.dart) | Guarda y recupera la clave de Gemini y los registros de auditoría usando `flutter_secure_storage`; limita el historial a 500 registros. |
| [`network_auditor.dart`](lib/network_auditor.dart) | Proporciona un stream de cambios del estado del escudo y una comprobación DNS puntual de `cloudflare.com`. Es una utilidad auxiliar, no un monitor continuo de tráfico. |
| [`voice_engine.dart`](lib/voice_engine.dart) | Configura `flutter_tts` en español (`es-ES`) y ofrece métodos para leer texto o detener la reproducción. |
| [`radar_waves.dart`](lib/radar_waves.dart) | Dibuja ondas animadas de radar con `CustomPainter`, utilizadas durante el escaneo. |
| [`services/aura_core.dart`](lib/services/aura_core.dart) | Servicio auxiliar que solicita telemetría Android y coordina su análisis proactivo, gestionando errores de plataforma y formato. |
| [`services/ai_brain.dart`](lib/services/ai_brain.dart) | Adaptador que serializa evento y registros de dispositivo como JSON y delega el análisis en `AuraAIBrain`. |
| [`secure_vault_core.dart`](lib/secure_vault_core.dart) | Implementación alternativa de persistencia basada en archivo temporal. Aplica XOR, no cifrado criptográfico, y no es la bóveda segura usada por `main.dart`; no debe emplearse para guardar secretos. |

El flujo de la pantalla principal usa estado local de Flutter (`StatefulWidget` y `setState`); el proyecto no declara un gestor de estado externo como Provider, Riverpod o BLoC. Los servicios auxiliares que no se importan desde `main.dart` no forman parte del flujo principal actual.

---

## 🛠️ Stack tecnológico

Versiones resueltas según `pubspec.lock`:

| Dependencia | Versión resuelta | Uso en Aura |
|---|---:|---|
| `google_generative_ai` | `0.4.7` | Cliente Dart para Gemini, generación de respuestas y llamadas a herramientas de seguridad. |
| `flutter_secure_storage` | `9.2.4` | Persistencia de la clave de API y registros locales mediante almacenamiento seguro; Android está configurado con `encryptedSharedPreferences`. |
| `flutter_tts` | `4.2.5` | Síntesis de voz de consultas, respuestas y alertas en español. |
| `cupertino_icons` | `1.0.9` | Iconos de interfaz de Cupertino disponibles para la UI Flutter. |

El proyecto declara Flutter mediante el SDK y requiere Dart `>=3.0.0 <4.0.0`. Las dependencias de desarrollo son `flutter_test` y `flutter_lints ^3.0.0`.

---

## 🚀 Inicio de la aplicación

`main()` ejecuta `AuraApp`, que configura `MaterialApp` con tema oscuro y establece `AuraCoreScreen` como pantalla inicial. La pantalla inicia la animación de Aura y la supervisión periódica de integridad; presenta el estado y los registros, un campo para consultas a Gemini, un control de escaneo y el botón del escudo VPN. Si todavía no hay una clave Gemini almacenada, permite introducirla para guardarla antes de repetir la consulta.

---

## ⚙️ CI/CD con Codemagic

El workflow `android-build` de [`codemagic.yaml`](codemagic.yaml) automatiza la generación del APK de producción:

1. Se ejecuta con eventos `push` en las ramas `main` y `principal`.
2. Usa una instancia `mac_mini_m1`, Flutter `3.47.5` y Java `21`, con una duración máxima configurada de 60 minutos.
3. Genera `android/local.properties` usando la ruta de Flutter proporcionada por el entorno.
4. Limpia el proyecto, descarga dependencias y ejecuta `flutter build apk --release`.
5. Define el modelo mediante `--dart-define=GEMINI_MODEL`; si la variable de entorno no está configurada, el comando usa `gemini-2.5-flash`.
6. Publica como artefacto los APK encontrados en `build/app/outputs/flutter-apk/*.apk`.

`GEMINI_MODEL` selecciona el modelo y no es la clave de API. La clave Gemini se configura en la aplicación y se guarda localmente mediante la bóveda; el workflow mostrado no inyecta una clave de API.

---

## 🔐 Consideraciones de seguridad

- El modo sin root evita depender de privilegios de superusuario, pero no elimina la necesidad de permisos Android ni de la autorización del usuario para iniciar el servicio VPN.
- La protección de `flutter_secure_storage` depende de la implementación de la plataforma. La configuración actual habilita `encryptedSharedPreferences`, pero no acredita por sí sola cifrado respaldado por hardware.
- `secure_vault_core.dart` contiene una alternativa XOR que no es adecuada para secretos. La bóveda usada por el flujo principal es `secure_vault.dart`.
- La comprobación DNS de `network_auditor.dart` valida resolución de nombres en una llamada puntual; no analiza paquetes ni demuestra que el tráfico esté libre de amenazas.

---

## 📦 Compilación local

```bash
flutter pub get
flutter build apk --release \
  --dart-define=GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
```

El APK de release se genera bajo `build/app/outputs/flutter-apk/`.