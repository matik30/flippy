import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flippy/theme/colors.dart';
import 'package:flippy/theme/fonts.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
                    children: [
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
          children: [
            // Gradient CircularProgressIndicator with rotation animation
            SizedBox(
              width: 140,
              height: 140,
              child: ClipOval(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, child) {
                        return Transform.rotate(
                          angle: _controller.value * 2 * 3.14, // otáča pomaly
                          child: ShaderMask(
                            shaderCallback: (rect) {
                              return SweepGradient(
                                startAngle: 0,
                                endAngle: 3.14 * 2,
                                colors: [
                                  AppColors.accent,
                                  AppColors.secondary.withValues(alpha: 0.4),
                                ],
                                stops: [0.0, 0.4],
                              ).createShader(rect);
                            },
                            child: CircularProgressIndicator(
                              strokeWidth: 12, // hrúbka kruhu
                              valueColor: const AlwaysStoppedAnimation(Colors.white),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        );
                      },
                  ),
              ),
            ),

                  // Placeholder loga
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'Logo',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // Názov aplikácie
            Text('Flippy', style: AppTextStyles.heading),
          ],
        ),
      ),
    );
  }
}
