-keep class com.ciberdefensa.aura.MainActivity { *; }
-keep class com.ciberdefensa.aura.AuraVpnService { *; }
-keep class hev.htproxy.TProxyService { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}