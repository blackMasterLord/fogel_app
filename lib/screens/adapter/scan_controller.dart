import 'package:fogel_app/services/wifi_channel.dart';

/// Manages WiFi scan state across page navigations.
/// Replaces static fields in AdapterConnectPage.
class ScanController {
  List<WifiNetworkInfo>? networks;
  String? scanError;
  bool scanning = false;
  bool suppressWifiRefresh = false;
  bool manualDisconnect = false;

  void start()  { scanning = true;  networks = []; scanError = null; }
  void stop()   { scanning = false; }
  void reset()  { networks = null; scanError = null; suppressWifiRefresh = false; }
  void setNetworks(List<WifiNetworkInfo> list) { networks = list; }
}
