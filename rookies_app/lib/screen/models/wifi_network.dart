class WiFiNetwork {
  final String ssid;
  final int rssi;
  final bool encrypted;

  WiFiNetwork({
    required this.ssid,
    required this.rssi,
    required this.encrypted,
  });
}
