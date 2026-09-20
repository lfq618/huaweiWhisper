import 'dart:math';
import 'package:flutter/material.dart';

class WaveformVisualizer extends StatelessWidget {
  final List<double> amplitudes;
  final bool isRecording;
  final bool isPaused;
  final Color barColor;

  const WaveformVisualizer({
    super.key,
    required this.amplitudes,
    required this.isRecording,
    this.isPaused = false,
    this.barColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRecording) {
      return const SizedBox(height: 36);
    }

    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(24, (index) {
          double factor = 0.2;
          if (!isPaused && amplitudes.isNotEmpty) {
            final ampIndex = (amplitudes.length - 1 - (23 - index));
            if (ampIndex >= 0 && ampIndex < amplitudes.length) {
              factor = amplitudes[ampIndex];
            } else {
              factor = 0.15 + (sin(index * 0.5) * 0.1).abs();
            }
          }

          factor = factor.clamp(0.12, 1.0);
          final barHeight = 6.0 + factor * 28.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 3.5,
            height: barHeight,
            decoration: BoxDecoration(
              color: isPaused
                  ? barColor.withValues(alpha: 0.4)
                  : barColor.withValues(alpha: 0.85 + (factor * 0.15)),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
