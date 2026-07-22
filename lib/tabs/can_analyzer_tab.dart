import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../services/fogel_adapter_service.dart';

enum SortMode { id, count, period }

/// Simple CAN entry — persists across tab switches via static map.
class _CanEntry {
  final int id;
  final bool isExtended;
  final int dlc;
  final List<int> data;
  final List<int>? prevData;
  final int period;
  final int timestamp;
  final int adapterCount;

  /// Cached hex strings — formatted once on creation, not on every rebuild.
  final String idHex;
  final List<String> dataHex;

  /// Per-byte change timestamps (ms since epoch). 0 = never changed.
  /// Used for 1-second highlight timeout.
  final List<int> byteChangeMs;

  _CanEntry({
    required this.id,
    required this.isExtended,
    required this.dlc,
    required this.data,
    this.prevData,
    required this.period,
    required this.timestamp,
    required this.adapterCount,
    required this.byteChangeMs,
  }) : idHex = id.toRadixString(16).toUpperCase(),
       dataHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).toList();
}

class CanAnalyzerTab extends StatefulWidget {
  const CanAnalyzerTab({super.key});

  @override
  State<CanAnalyzerTab> createState() => _CanAnalyzerTabState();
}

class _CanAnalyzerTabState extends State<CanAnalyzerTab> {
  static final Map<int, _CanEntry> _entries = {};

  /// Incremented on each CAN batch to trigger card-list rebuild only.
  static final ValueNotifier<int> _entriesVersion = ValueNotifier(0);

  /// Cached sorted ID list — rebuilt only when new IDs appear.
  static final List<int> _sortedIds = [];
  static bool _sortedIdsDirty = true;

  /// Max unique CAN IDs before evicting oldest entries.
  static const int _maxEntries = 500;
  static const int _highlightDurationMs = 1000;

  int? _lastCanSpeed;
  bool _isPaused = false;

  // --- Sort state ---
  SortMode _sortMode = SortMode.id;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _lastCanSpeed = globalSettings.value.canSpeed;
    globalSettings.addListener(_onSettingsChanged);
    FogelAdapterService.canMessagesNotifier.addListener(_onCanMessagesChanged);
  }

  @override
  void dispose() {
    globalSettings.removeListener(_onSettingsChanged);
    FogelAdapterService.canMessagesNotifier.removeListener(_onCanMessagesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    final speed = globalSettings.value.canSpeed;
    if (speed != _lastCanSpeed) {
      _lastCanSpeed = speed;
      _entries.clear();
      _sortedIdsDirty = true;
      _sortedIds.clear();
      _entriesVersion.value++;
    }
  }

  void _onCanMessagesChanged() {
    if (_isPaused) return;
    final messages = FogelAdapterService.canMessagesNotifier.value;
    if (messages.isEmpty) return;

    for (final msg in messages) {
      final prev = _entries[msg.id];
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final byteLen = msg.data.length > 8 ? 8 : msg.data.length;

      // Evict oldest entry if at capacity and this is a new ID
      if (prev == null && _entries.length >= _maxEntries) {
        final oldest = _entries.entries.reduce(
          (a, b) => a.value.timestamp < b.value.timestamp ? a : b);
        _entries.remove(oldest.key);
      }

      // Compute per-byte change timestamps
      final newByteChangeMs = List.filled(8, 0);
      for (int bi = 0; bi < byteLen; bi++) {
        if (prev != null && bi < prev.data.length && msg.data[bi] != prev.data[bi]) {
          newByteChangeMs[bi] = nowMs;
        } else if (prev != null && bi < prev.byteChangeMs.length) {
          newByteChangeMs[bi] = prev.byteChangeMs[bi];
        }
      }

      _entries[msg.id] = _CanEntry(
        id: msg.id,
        isExtended: msg.id > 0x7FF,
        dlc: msg.dlc,
        data: List.of(msg.data),
        prevData: prev?.data,
        period: msg.period,
        timestamp: msg.timestamp.millisecondsSinceEpoch,
        adapterCount: msg.count,
        byteChangeMs: newByteChangeMs,
      );

      if (prev == null) {
        _sortedIdsDirty = true;
      }
    }
    _entriesVersion.value++;
  }

  void _clear() {
    _isPaused = false;
    FogelAdapterService().sendClearCan();
    FogelAdapterService.resetCanMessages();
    _entries.clear();
    _sortMode = SortMode.id;
    _sortedIdsDirty = true;
    _sortedIds.clear();
    _entriesVersion.value++;
  }

  /// Sort comparator with support for multiple modes.
  /// For equal periods/counts — falls back to ID sort.
  int _compareCanId(int a, int b) {
    if (_sortMode == SortMode.id) {
      final aExt = a > 0x7FF;
      final bExt = b > 0x7FF;
      if (aExt != bExt) return aExt ? 1 : -1;
      return a.compareTo(b);
    }

    final ea = _entries[a];
    final eb = _entries[b];

    if (_sortMode == SortMode.period) {
      final cmp = (ea?.period ?? 0).compareTo(eb?.period ?? 0);
      if (cmp != 0) return cmp;
    } else if (_sortMode == SortMode.count) {
      final cmp = (ea?.adapterCount ?? 0).compareTo(eb?.adapterCount ?? 0);
      if (cmp != 0) return cmp;
    }

    // Fallback to ID sort on equal values
    final aExt = a > 0x7FF;
    final bExt = b > 0x7FF;
    if (aExt != bExt) return aExt ? 1 : -1;
    return a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FogelSettings>(
      valueListenable: globalSettings,
      builder: (context, settings, _) {
        final isConnected = settings.connectionStatus == 'connected';
        final isAutoDetecting = settings.isAutoDetecting;

        return Column(
          children: [
            _buildSpeedRow(settings, isConnected, isAutoDetecting),
            const Divider(height: 1),
            Expanded(child: _buildBody(isConnected)),
          ],
        );
      },
    );
  }

  // ─── Body: disconnected / always-visible toolbar+header / list ─────

  Widget _buildBody(bool isConnected) {
    return ValueListenableBuilder<int>(
      valueListenable: _entriesVersion,
      builder: (context, _, _) {
        if (!isConnected) {
          return const Center(
            child: Text('Адаптер не подключен',
              style: TextStyle(color: Colors.grey)),
          );
        }
        return Column(
          children: [
            _buildToolbar(),
            _buildTableHeader(),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hourglass_empty, size: 40, color: Colors.grey.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                            _isPaused ? 'Пауза — нет данных' : 'Ожидание CAN-сообщений...',
                            style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    )
                  : _buildCanList(),
            ),
          ],
        );
      },
    );
  }

  // ─── Speed dropdown ─────────────────────────────────────────

  Widget _buildSpeedRow(FogelSettings settings, bool isConnected, bool isAutoDetecting) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Скорость CAN-шины:', 
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButton<int>(
            value: (isConnected && !isAutoDetecting) ? settings.canSpeed : null,
            hint: const Text('Нет', style: TextStyle(color: Colors.grey)),
            disabledHint: const Text('Недоступно', style: TextStyle(color: Colors.grey)),
            onChanged: (isConnected && !isAutoDetecting && settings.availableCanSpeeds.isNotEmpty)
                ? (v) {
                    if (v == null) return;
                    if (v == -1) {
                      FogelAdapterService().setSpeedAuto();
                    } else {
                      globalSettings.value = settings.copyWith(canSpeed: v);
                      FogelAdapterService().setSpeed(v);
                    }
                  }
                : null,
            items: isConnected
                ? [
                    ...settings.availableCanSpeeds.map((v) => DropdownMenuItem(value: v, child: Text('$v kbps'))),
                    if (settings.hasAutoSpeed) const DropdownMenuItem(value: -1, child: Text('AUTO')),
                  ]
                : null,
          ),
        ],
      ),
    );
  }

  // ─── Toolbar + table ────────────────────────────────────

  Widget _buildToolbar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          ValueListenableBuilder<CanStats>(
            valueListenable: canStatsNotifier,
            builder: (context, stats, _) => Text(
              '${_entries.length} ID · ${stats.totalMessages}',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
          const Spacer(),
          DropdownButton<SortMode>(
            value: _sortMode,
            onChanged: (mode) {
              if (mode == null) return;
              setState(() {
                _sortMode = mode;
                _sortedIdsDirty = true;
                _entriesVersion.value++;
              });
            },
            items: const [
              DropdownMenuItem(value: SortMode.id, child: Text('По ID')),
              DropdownMenuItem(value: SortMode.count, child: Text('По кол-ву')),
              DropdownMenuItem(value: SortMode.period, child: Text('По периоду')),
            ],
          ),
          IconButton(
            icon: Icon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              size: 20,
              color: _isPaused ? Colors.orange : null,
            ),
            onPressed: () => setState(() => _isPaused = !_isPaused),
            tooltip: _isPaused ? 'Продолжить' : 'Пауза',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: _clear,
            tooltip: 'Очистить',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('ID',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
          ),
          SizedBox(
            width: 28,
            child: Text('DLC',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
          ),
          SizedBox(
            width: 48,
            child: Text('Период',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
          ),
          const Spacer(),
          SizedBox(
            width: 36,
            child: Text('К-во',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildCanList() {
    if (_sortedIdsDirty) {
      _sortedIds
        ..clear()
        ..addAll(_entries.keys)
        ..sort(_compareCanId);
      _sortedIdsDirty = false;
    }

    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemHeight = constraints.maxHeight / 6;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            key: const ValueKey('can_list'),
            controller: _scrollController,
            itemExtent: itemHeight,
            itemCount: _sortedIds.length,
            itemBuilder: (context, index) {
              final entry = _entries[_sortedIds[index]]!;
              return _buildRow(entry, index, scheme, itemHeight);
            },
          ),
        );
      },
    );
  }

  // ─── Compact 2-line row ──────────────────────────────────

  Widget _buildRow(_CanEntry entry, int index, ColorScheme scheme, double itemHeight) {
    final isEven = index.isEven;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hasChanges = entry.byteChangeMs.any((ms) => ms > 0 && (nowMs - ms) < _highlightDurationMs);

    return Container(
      height: itemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isEven ? null : scheme.surfaceContainerHighest.withValues(alpha: 0.15),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Column(
        children: [
          // Line 1: metadata
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.idHex,
                    style: TextStyle(
                      color: entry.isExtended ? Colors.orange.shade700 : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text('${entry.dlc}',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    entry.period > 0 ? '${entry.period}мс' : '-',
                    style: TextStyle(color: scheme.primary),
                  ),
                ),
                const Spacer(),
                Text(
                  '${entry.adapterCount}',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
                ),
                const SizedBox(width: 4),
                if (hasChanges)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),
          // Line 2: data bytes
          Expanded(
            child: Row(
              children: List.generate(entry.dlc > 8 ? 8 : entry.dlc, (i) {
                final justChanged = entry.byteChangeMs[i] > 0 &&
                    (nowMs - entry.byteChangeMs[i]) < _highlightDurationMs;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: justChanged ? Colors.red.withValues(alpha: 0.15) : null,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      entry.dataHex[i],
                      style: TextStyle(
                        color: justChanged ? Colors.red.shade700 : null,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}