import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

const _glowColor = Color(0xFF40C4FF);

class LightningIconWithParticles extends StatefulWidget {
  const LightningIconWithParticles({super.key});

  @override
  State<LightningIconWithParticles> createState() => _LightningIconWithParticlesState();
}

class _LightningIconWithParticlesState extends State<LightningIconWithParticles> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<LightningStrike> _currentStrikes = [];
  final Random _random = Random();
  Timer? _spawnTimer;

  /// Dedicated repaint trigger — avoids setState-driven widget rebuilds on every
  /// animation frame. Only the CustomPaint layer repaints when this changes.
  final ValueNotifier<int> _repaintNotifier = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        _updateStrike();
      });

    _startSpawnCycle();
  }

  void _startSpawnCycle() {
    _scheduleNextStrike();
  }

  void _scheduleNextStrike() {
    _spawnTimer?.cancel();
    
    final randomDelay = _random.nextInt(1501) + 500;

    _spawnTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (mounted) {
        if (_currentStrikes.isEmpty) {
          _generateStrike();
        }
        _scheduleNextStrike();
      }
    });
  }

  void _generateStrike() {
    setState(() {
      _currentStrikes.clear();
      final strikeCount = _random.nextInt(3) + 1;

      for (int i = 0; i < strikeCount; i++) {
        final angle = _random.nextDouble() * 2 * pi;
        final mainPath = _generateJaggedPath(Offset.zero, angle, 24.0, 4);

        final branches = <List<Offset>>[];
        if (mainPath.length >= 3) {
          if (_random.nextDouble() < 0.6) {
            final branchStart = mainPath[1];
            final branchAngle = angle + (_random.nextDouble() * 0.8 - 0.4);
            branches.add(_generateJaggedPath(branchStart, branchAngle, 12.0, 2));
          }
        }

        _currentStrikes.add(LightningStrike(
          angle: angle,
          mainPath: mainPath,
          branches: branches,
        ));
      }
    });
    _controller.forward(from: 0.0);
  }

  List<Offset> _generateJaggedPath(Offset start, double angle, double length, int segments) {
    final List<Offset> path = [start];
    final stepLength = length / segments;

    for (int i = 1; i <= segments; i++) {
      final currentDist = stepLength * i;
      final straightX = start.dx + cos(angle) * currentDist;
      final straightY = start.dy + sin(angle) * currentDist;

      final perpAngle = angle + pi / 2;
      final displacement = (_random.nextDouble() * 6.0 - 3.0) * (i / segments); 
      final jaggedX = straightX + cos(perpAngle) * displacement;
      final jaggedY = straightY + sin(perpAngle) * displacement;

      path.add(Offset(jaggedX, jaggedY));
    }
    return path;
  }

  void _updateStrike() {
    if (_currentStrikes.isEmpty) return;

    final t = _controller.value;
    double opacity = 0.0;
    if (t < 0.2) {
      opacity = 1.0;
    } else if (t < 0.4) {
      opacity = 0.1;
    } else if (t < 0.7) {
      opacity = 0.8;
    } else {
      opacity = 0.0;
    }

    for (var strike in _currentStrikes) {
      strike.opacity = opacity;
    }

    if (t == 1.0) {
      // Strike sequence complete — need a structural rebuild to remove the painter.
      setState(() {
        _currentStrikes.clear();
      });
    } else {
      // Opacity-only change — repaint just the CustomPaint layer without
      // rebuilding the whole widget tree (AppBar, Scaffold, etc.).
      _repaintNotifier.value++;
    }
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _controller.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (_currentStrikes.isNotEmpty)
            Positioned(
              left: -20,
              top: -20,
              child: CustomPaint(
                size: const Size(64, 64),
                painter: LightningStrikePainter(_currentStrikes, repaint: _repaintNotifier),
              ),
            ),
          const Icon(Icons.bolt, color: Colors.white, size: 24),
        ],
      ),
    );
  }
}

class LightningStrike {
  final double angle;
  final List<Offset> mainPath;
  final List<List<Offset>> branches;
  double opacity;

  LightningStrike({
    required this.angle,
    required this.mainPath,
    required this.branches,
    this.opacity = 1.0,
  });
}

class LightningStrikePainter extends CustomPainter {
  final List<LightningStrike> strikes;

  LightningStrikePainter(this.strikes, {super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final strike in strikes) {
      final glowPaint = Paint()
        ..color = _glowColor.withValues(alpha: strike.opacity * 0.4)
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: strike.opacity)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawStrike(canvas, center, glowPaint, strike);
      _drawStrike(canvas, center, corePaint, strike);
    }
  }

  void _drawStrike(Canvas canvas, Offset center, Paint paint, LightningStrike strike) {
    final mainPath = Path();
    if (strike.mainPath.isNotEmpty) {
      mainPath.moveTo(center.dx + strike.mainPath[0].dx, center.dy + strike.mainPath[0].dy);
      for (int i = 1; i < strike.mainPath.length; i++) {
        mainPath.lineTo(center.dx + strike.mainPath[i].dx, center.dy + strike.mainPath[i].dy);
      }
    }
    canvas.drawPath(mainPath, paint);

    for (final branch in strike.branches) {
      final branchPath = Path();
      if (branch.isNotEmpty) {
        branchPath.moveTo(center.dx + branch[0].dx, center.dy + branch[0].dy);
        for (int i = 1; i < branch.length; i++) {
          branchPath.lineTo(center.dx + branch[i].dx, center.dy + branch[i].dy);
        }
      }
      canvas.drawPath(branchPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LightningStrikePainter oldDelegate) =>
      strikes != oldDelegate.strikes;
}