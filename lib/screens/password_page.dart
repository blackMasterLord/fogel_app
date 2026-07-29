import 'dart:async';
import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../services/fogel_adapter_service.dart';

class PasswordPage extends StatefulWidget {
  final SavedDevice device;
  final Future<bool> Function(SavedDevice device, bool remember, String password) connectFn;

  const PasswordPage({super.key, required this.device, required this.connectFn});

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _connecting = false;
  bool _highlightError = false;
  bool _passwordValid = false;
  bool _remember = true;
  Timer? _highlightTimer;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    globalSettings.addListener(_onSettingsChanged);
    _shakeController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 250)
    );
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    final valid = _validateWpa2(_passwordController.text);
    if (valid != _passwordValid) setState(() => _passwordValid = valid);
  }

  bool _validateWpa2(String? value) {
    if (value == null || value.isEmpty) return false;
    final wpa2Regex = RegExp(r'^[\x20-\x7E]{8,63}$');
    return wpa2Regex.hasMatch(value);
  }

  @override
  void dispose() {
    globalSettings.removeListener(_onSettingsChanged);
    _passwordController.dispose();
    _highlightTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (!_connecting && globalSettings.value.connectionStatus == FogelConnectionState.disconnected) {
      Navigator.pop(context);
    }
  }

  Future<void> _submit() async {
    if (_connecting) return;
    FocusScope.of(context).unfocus();

    if (_passwordController.text.isEmpty) {
      _highlightTimer?.cancel();
      setState(() => _highlightError = true);
      _shakeController.forward(from: 0);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightError = false);
      });
      return;
    }

    // WPA2 password validation: 8–63 ASCII characters
    final pwd = _passwordController.text;
    if (!_validateWpa2(pwd)) {
      _highlightTimer?.cancel();
      setState(() => _highlightError = true);
      _shakeController.forward(from: 0);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightError = false);
      });
      return;
    }

    setState(() => _connecting = true);

    final deviceWithPassword = SavedDevice(address: widget.device.address, name: widget.device.name);

    try {
      final success = await widget.connectFn(deviceWithPassword, _remember, pwd);
      if (!mounted) return;

      if (success) {
        Navigator.pop(context);
      } else {
        _passwordController.clear();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка подключения'), 
          backgroundColor: Colors.red
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_connecting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Отменить подключение?'),
            content: const Text('WiFi-подключение будет разорвано.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да, отменить')),
            ],
          ),
        );
        if (ok == true) {
          FogelAdapterService().disconnect(manual: true, disconnectWifi: true);
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Подключение адаптера')),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.device.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final dx = sin(_shakeController.value * 4 * pi) * 8 * (1 - _shakeController.value);
                    return Transform.translate(offset: Offset(dx, 0), child: child);
                  },
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscureText,
                    enabled: !_connecting,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      border: const OutlineInputBorder(),
                      //prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _highlightError ? 'Ошибка' : null,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureText = !_obscureText),
                      ),
                    ),
                  ),
                ),
                //const SizedBox(height: 6),
                Row(children: [
                  Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? true)),
                  const Text('Запомнить'),
                ]),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (_connecting || !_passwordValid) ? null : _submit,
                  icon: _connecting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : null,
                  label: Text(_connecting ? 'Подключение...' : 'Подключиться'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
