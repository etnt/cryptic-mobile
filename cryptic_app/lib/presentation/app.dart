// lib/presentation/app.dart
//
// Root application widget
//

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/logger.dart';
import 'providers/auth_provider.dart';
import 'providers/enrollment_provider.dart';
import 'screens/conversations_screen.dart';
import 'screens/enrollment/enrollment_flow_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/users_screen.dart';

/// App navigation state.
enum AppScreen {
  /// Splash/loading screen.
  splash,
  /// Enrollment flow (no certificates yet).
  enrollment,
  /// Login/setup screen.
  login,
  /// Main conversations screen.
  home,
}

/// Root application widget.
///
/// Sets up the MaterialApp with theming, routing, and global configuration.
class CrypticApp extends ConsumerStatefulWidget {
  /// Creates the root application widget.
  const CrypticApp({super.key});

  @override
  ConsumerState<CrypticApp> createState() => _CrypticAppState();
}

class _CrypticAppState extends ConsumerState<CrypticApp> {
  AppScreen _currentScreen = AppScreen.splash;

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('Building CrypticApp', tag: 'App');

    // Listen to auth state changes
    ref.listen<AuthStatus>(authProvider, (previous, next) {
      if (next.isAuthenticated && _currentScreen != AppScreen.home) {
        setState(() {
          _currentScreen = AppScreen.home;
        });
      } else if (!next.isAuthenticated && _currentScreen == AppScreen.home) {
        setState(() {
          _currentScreen = AppScreen.login;
        });
      }
    });

    return MaterialApp(
      title: 'Cryptic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    return switch (_currentScreen) {
      AppScreen.splash => SplashScreen(
          onInitialized: (needsSetup) {
            setState(() {
              _currentScreen =
                  needsSetup ? AppScreen.enrollment : AppScreen.login;
            });
          },
        ),
      AppScreen.enrollment => EnrollmentFlowScreen(
          onComplete: () {
            ref.read(enrollmentProvider.notifier).reset();
            setState(() {
              _currentScreen = AppScreen.login;
            });
          },
        ),
      AppScreen.login => LoginScreen(
          onLoginSuccess: () {
            setState(() {
              _currentScreen = AppScreen.home;
            });
          },
        ),
      AppScreen.home => const UsersScreen(),
    };
  }
}
