-keep class com.ciberdefensa.aura.MainActivity { *; }
-keep class com.ciberdefensa.aura.AuraVpnService { *; }
-keep class hev.htproxy.TProxyService { *; }
-keep class com.aura.cyberdefense.AuraCryptoSecure { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}