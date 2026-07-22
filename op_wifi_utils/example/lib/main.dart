import 'package:flutter/material.dart';
import 'package:op_wifi_utils/op_wifi_utils.dart';

void main() {
  runApp(const WifiUtilsExampleApp());
}

class WifiUtilsExampleApp extends StatelessWidget {
  const WifiUtilsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: WifiExampleHome());
  }
}

class WifiExampleHome extends StatefulWidget {
  const WifiExampleHome({super.key});

  @override
  State<WifiExampleHome> createState() => _WifiExampleHomeState();
}

class _WifiExampleHomeState extends State<WifiExampleHome> {
  String _output = '';

  Future<void> _connect() async {
    final result = await OpWifiUtils.connectToWifi(
      ssid: 'Your_SSID',
      password: 'YourPassword',
    );
    setState(() {
      _output = result.isSuccess
          ? 'Connected successfully!'
          : 'Connection failed: ${result.error.type}';
    });
  }

  Future<void> _disconnect() async {
    final result = await OpWifiUtils.disconnectFromWifi('Your_SSID');
    setState(() {
      _output = result.isSuccess
          ? 'Disconnected successfully!'
          : 'Disconnection failed: ${result.error.type}';
    });
  }

  Future<void> _getCurrentSsid() async {
    final result = await OpWifiUtils.getCurrentSsid();
    setState(() {
      _output = result.isSuccess
          ? 'Current SSID: "${result.data}"'
          : 'Failed to get SSID: ${result.error.type}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('op_wifi_utils Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: _connect, child: const Text('Connect')),
            ElevatedButton(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            ),
            ElevatedButton(
              onPressed: _getCurrentSsid,
              child: const Text('Get Current SSID'),
            ),
            const SizedBox(height: 20),
            Text(_output),
          ],
        ),
      ),
    );
  }
}
