abstract class AuraWhitelist {
  static const Set<String> _topSafeDomains = <String>{
    'google.com',
    'apple.com',
    'microsoft.com',
    'amazonaws.com',
    'cloudflare.com',
    'akamaiedge.net',
    'android.com',
    'github.com',
    'whatsapp.net',
    'googleapis.com',
    'gstatic.com',
    'googleusercontent.com',
    'apple-dns.net',
    'icloud.com',
    'microsoftonline.com',
    'windows.net',
    'amazon.com',
    'awsstatic.com',
    'akamaized.net',
    'fastly.net',
  };

  static bool isSafe(String domain) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final candidate = normalized.contains('://') ? normalized : '//$normalized';
    final parsedHost = Uri.tryParse(candidate)?.host;
    if (parsedHost == null || parsedHost.isEmpty) return false;

    final host = parsedHost.endsWith('.')
        ? parsedHost.substring(0, parsedHost.length - 1)
        : parsedHost;
    if (host.isEmpty) return false;

    return _topSafeDomains.any(
      (safeDomain) => host == safeDomain || host.endsWith('.$safeDomain'),
    );
  }
}
