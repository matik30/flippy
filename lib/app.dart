import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'features/home/home_screen.dart';
import 'features/splash/splash_page.dart';
import 'features/chapters/chapters_screen.dart';
import 'features/lessons/lesson_screen.dart';
import 'features/scan/qr_scan_page.dart';
import 'theme/theme_notifier.dart';

class FlippyApp extends StatelessWidget {
  const FlippyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tn = Provider.of<ThemeNotifier>(context);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: tn.theme,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(path: '/qr', builder: (_, __) => const QrScanPage()),
    GoRoute(
      path: '/chapters',
      builder: (ctx, state) {
        final book = state.extra as Map<String, dynamic>?; // extra posielané z HomePage
        if (book == null) {
          return const Scaffold(body: Center(child: Text('No book provided')));
        }
        return BookScreen(book: book);
      },
    ),
    GoRoute(
      path: '/lessons',
      builder: (_, state) {
        final args = state.extra as Map<String, dynamic>?;
        return LessonScreen(args: args);
      },
    ),
  ],
);

// theme and fonts handled by ThemeNotifier and theme files
