import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/crash_log.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {

  String _version = '—';
  String _releaseDate = '—';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final versionStr = '${info.version}+${info.buildNumber}';

      final now = DateTime.now();
      const months = [
        '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
      ];
      final dateStr = '${months[now.month]} ${now.year}';

      if (mounted) {
        setState(() {
          _version = versionStr;
          _releaseDate = dateStr;
        });
      }
    } catch (_) {
      // package_info_plus not available — keep defaults
    }
  }

  Future<void> _shareLog(BuildContext context) async {
    try {
      final file = crashLogFile;
      if (!file.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл логов не найден'),
            ),
          );
        }
        return;
      }

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')]
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'), 
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearLog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить логи?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = crashLogFile;
        if (file.existsSync()) {
          file.deleteSync();
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Логи очищены'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: $e'), 
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final logoWidth = (screenWidth * 0.8);
    final logExists = crashLogFile.existsSync();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('О приложении'),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.white,
            ],
            stops: [0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.only(
                            top: 80,
                            bottom: 100,
                            left: (screenWidth - logoWidth) / 2,
                            right: (screenWidth - logoWidth) / 2,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/logo.webp',
                              width: logoWidth,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  'FogelApp',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  'Приложение для мониторинга CAN-шины и управления АКБ и ЗУ по разным протоколам с помощью Fogel Adapter.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Spacer(),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: GestureDetector(
                                  onLongPress: logExists ? () => _clearLog(context) : null,
                                  child: TextButton.icon(
                                    onPressed: logExists ? () => _shareLog(context) : null,
                                    icon: Icon(Icons.share, color: logExists
                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                                        : theme.colorScheme.onSurface.withValues(alpha: 0.25)),
                                    label: Text('Отправить логи', style: TextStyle(
                                        fontSize: 12,
                                        color: logExists
                                            ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                                            : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(alpha: logExists ? 0.2 : 0.08),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  'По всем вопросам обращайтесь в отдел RnD🤙',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  'Версия ПО: $_version · $_releaseDate',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
