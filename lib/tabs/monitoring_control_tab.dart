import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../services/fogel_adapter_service.dart';

class MonitoringControlTab extends StatefulWidget {
  const MonitoringControlTab({super.key});

  @override
  State<MonitoringControlTab> createState() => _MonitoringControlTabState();
}

class _MonitoringControlTabState extends State<MonitoringControlTab> {
  final ScrollController _scrollController = ScrollController();
  final FogelAdapterService _adapter = FogelAdapterService();

  // Track state changes to avoid unconditional setState on every TICK
  String _lastConnectionStatus = 'disconnected';
  bool _lastIsAutoDetecting = false;
  bool _lastIsLoadingProtocol = false;

  @override
  void initState() {
    super.initState();
    final s = globalSettings.value;
    _lastConnectionStatus = s.connectionStatus;
    _lastIsAutoDetecting = s.isAutoDetecting;
    _lastIsLoadingProtocol = _adapter.isLoadingProtocol.value;
    globalSettings.addListener(_onGlobalSettingsChanged);
    _adapter.isLoadingProtocol.addListener(_onLoadingProtocolChanged);
  }

  @override
  void dispose() {
    globalSettings.removeListener(_onGlobalSettingsChanged);
    _adapter.isLoadingProtocol.removeListener(_onLoadingProtocolChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onGlobalSettingsChanged() {
    final s = globalSettings.value;
    if (s.connectionStatus != _lastConnectionStatus ||
        s.isAutoDetecting != _lastIsAutoDetecting) {
      _lastConnectionStatus = s.connectionStatus;
      _lastIsAutoDetecting = s.isAutoDetecting;
      if (mounted) setState(() {});
    }
  }

  void _onLoadingProtocolChanged() {
    final loading = _adapter.isLoadingProtocol.value;
    if (loading != _lastIsLoadingProtocol) {
      _lastIsLoadingProtocol = loading;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = globalSettings.value;
    final isConnected = settings.connectionStatus == 'connected';
    final hasProtocol = settings.selectedProtocol != null;
    final showData = isConnected && hasProtocol;
    final isLoadingProto = _adapter.isLoadingProtocol.value;
    final isAutoDetecting = settings.isAutoDetecting;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Протокол связи:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoadingProto || isAutoDetecting)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  DropdownButton<String>(
                    value: isConnected ? settings.selectedProtocol : null,
                    hint: const Text('Не выбран', style: TextStyle(color: Colors.grey)),
                    disabledHint: const Text('Недоступно', style: TextStyle(color: Colors.grey)),
                    onChanged: (isConnected && !isLoadingProto && !isAutoDetecting)
                        ? (newValue) {
                            if (newValue != null) {
                              _adapter.selectProtocol(newValue);
                            }
                          }
                        : null,
                    items: isConnected
                        ? settings.availableProtocols.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList()
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: showData
              ? ValueListenableBuilder<BmsData>(
                  valueListenable: bmsNotifier,
                  builder: (context, bms, _) {
                    final cellCount = bms.cellCount ?? 16;
                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          _buildSectionHeader('Параметры АКБ'),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricTile(
                                  title: 'Напряжение АКБ',
                                  value: bms.batteryVoltage != null ? '${bms.batteryVoltage!.toStringAsFixed(1)} В' : '-- В',
                                  icon: Icons.electric_bolt,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildMetricTile(
                                  title: 'Заряд (SOC)',
                                  value: bms.soc != null ? '${bms.soc!.toStringAsFixed(1)} %' : '-- %',
                                  icon: Icons.battery_charging_full,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricTile(
                                  title: 'Температура',
                                  value: bms.temperature != null ? '${bms.temperature!.toStringAsFixed(1)} °C' : '-- °C',
                                  icon: Icons.thermostat,
                                  color: Colors.redAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildMetricTile(
                                  title: 'Ток заряда',
                                  value: bms.chargeCurrent != null ? '${bms.chargeCurrent!.toStringAsFixed(1)} А' : '-- А',
                                  icon: Icons.arrow_downward,
                                  color: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricTile(
                                  title: 'Ток разряда',
                                  value: bms.dischargeCurrent != null ? '${bms.dischargeCurrent!.toStringAsFixed(1)} А' : '-- А',
                                  icon: Icons.arrow_upward,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),

                          const SizedBox(height: 24),
                          _buildSectionHeader('Ячейки питания (${cellCount}S)'),

                          // Wrap with LayoutBuilder avoids shrinkWrap:true + GridView
                          // inside ListView — all cells are built lazily by ListView
                          // but laid out without each cell being a separate grid item.
                          LayoutBuilder(
                            builder: (context, constraints) {
                              const crossAxisCount = 4;
                              const spacing = 8.0;
                              final cellWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: List.generate(cellCount, (index) {
                                  final voltage = index < bms.cellVoltages.length
                                      ? bms.cellVoltages[index]
                                      : 0.0;
                                  return SizedBox(
                                    width: cellWidth,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text('Ячейка ${index + 1}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                          Text(
                                            '${voltage.toStringAsFixed(3)} В',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),

                          const SizedBox(height: 24),
                          _buildSectionHeader('Контакторы'),
                          _buildContactorRow(
                            label: 'Разряд',
                            icon: Icons.arrow_upward,
                            isActive: bms.dischargeOn,
                            showData: showData,
                            commandType: 'DISCHARGE',
                          ),
                          const SizedBox(height: 8),
                          _buildContactorRow(
                            label: 'Заряд',
                            icon: Icons.arrow_downward,
                            isActive: bms.chargeOn,
                            showData: showData,
                            commandType: 'CHARGE',
                          ),
                          const SizedBox(height: 8),
                          _buildContactorRow(
                            label: 'Предзаряд',
                            icon: Icons.battery_charging_full,
                            isActive: bms.prechargeOn,
                            showData: showData,
                            commandType: 'PRECHARGE',
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Center(
                  child: Text(
                    isConnected
                        ? 'Необходимо выбрать протокол связи'
                        : 'Адаптер не подключен',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.withValues(alpha: 0.6),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactorRow({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool showData,
    required String commandType,
  }) {
    return ValueListenableBuilder<String?>(
      valueListenable: _adapter.pendingCommand,
      builder: (context, pending, _) {
        final isLoading = pending == commandType;
        final isBusy = pending != null;
        final enabled = showData && !isBusy;

        final statusColor = !showData ? Colors.grey : isActive ? Colors.green : Colors.red;

        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 20, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        !showData ? 'Неизвестно' : isActive ? 'ВКЛЮЧЕН' : 'ОТКЛЮЧЕН',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                Switch(
                  value: showData ? isActive : false,
                  onChanged: enabled
                      ? (value) => _adapter.sendCommand(commandType, value)
                      : null,
                  activeThumbColor: Colors.green,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}
