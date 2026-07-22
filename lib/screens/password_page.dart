import 'dart:async';
import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';

class PasswordPage extends StatefulWidget {
  final SavedDevice device;
  final Future<bool> Function(SavedDevice device, bool remember) connectFn;

  const PasswordPage({
    super.key,
    required this.device,
    required this.connectFn,
  });

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage>
    with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _remember = true;
  bool _connecting = false;
  bool _highlightError = false;
  Timer? _highlightTimer;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    globalSettings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    globalSettings.removeListener(_onSettingsChanged);
    _highlightTimer?.cancel();
    _shakeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (!_connecting && globalSettings.value.connectionStatus == 'disconnected') {
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

    setState(() => _connecting = true);

    final deviceWithPassword = SavedDevice(
      address: widget.device.address,
      name: widget.device.name,
      password: _passwordController.text,
    );

    try {
      final success = await widget.connectFn(deviceWithPassword, _remember);
      if (!mounted) return;

      if (success) {
        Navigator.pop(context);
      } else {
        _passwordController.clear();
        // Error UI handled by _connectToDevice (connectionError banner)
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка подключения'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = _highlightError ? Colors.red : theme.colorScheme.outline;

    return Scaffold(
      appBar: AppBar(title: const Text('Подключение адаптера')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.wifi_lock, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                widget.device.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
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
                    border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor, width: 2)),
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() => _obscureText = !_obscureText),
                      child: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _remember,
                onChanged: _connecting ? null : (v) => setState(() => _remember = v ?? true),
                title: const Text('Запомнить', style: TextStyle(fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _connecting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: theme.colorScheme.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _connecting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Подключить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
