package hev.htproxy;

public final class TProxyService {
    static {
        System.loadLibrary("hev-socks5-tunnel");
    }

    private TProxyService() {
    }

    public static native boolean TProxyStartService(String configPath, int tunFd);

    public static native boolean TProxyStopService();

    public static native boolean TProxyIsRunning();

    public static native long[] TProxyGetStats();

    public static native void TProxySetBlockedIps(String[] addresses);

    public static native boolean TProxyBlockDomain(String domain);

    public static void dispatchDnsEvent(
            String domain, int action, String sourceAddress, int sourcePort) {
        com.ciberdefensa.aura.AuraNetworkStream.INSTANCE.emitDnsEvent(
                domain, action == 1, sourceAddress, sourcePort);
    }
}