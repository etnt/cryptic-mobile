// lib/presentation/app.dart
//
// Root application widget
//

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/update/update_prompt.dart';
import '../core/utils/logger.dart';
import '../data/engine/engine_state.dart';
import '../data/services/notification_service.dart';
import '../domain/models/message.dart';
import 'providers/auth_provider.dart';
import 'providers/engine_provider.dart';
import 'providers/enrollment_provider.dart';
import 'providers/messages_provider.dart';
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
  int _loginKey = 0;

  /// Lets the startup update check show a dialog with a valid Navigator
  /// context (this State sits above the MaterialApp's own Navigator).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Check GitHub Releases for a newer side-loaded APK once, after first
    // frame so a Navigator/Overlay is available for the prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _navigatorKey.currentContext;
      if (ctx != null) {
        checkAndPromptForUpdate(ctx);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('Building CrypticApp', tag: 'App');

    // Globally persist incoming messages regardless of which screen is open.
    // Without this, messages arriving while the ChatScreen is not mounted
    // (e.g. pending messages delivered on connect) would be lost.
    ref.listen<AsyncValue<EngineEvent>>(engineEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is MessageReceived) {
          final repo = ref.read(messageRepositoryProvider);
          if (repo != null) {
            final msg = ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              conversationId: event.fromUser,
              senderId: event.fromUser,
              content: event.plaintext,
              timestamp: event.timestamp,
              direction: MessageDirection.incoming,
              status: MessageStatus.delivered,
            );
            repo.saveIncomingMessage(msg);
            ref.read(conversationsProvider.notifier).addMessage(
                  event.fromUser,
                  msg,
                );

            // Show local notification (suppressed if that chat is open)
            NotificationService.instance.showMessageNotification(
              fromUser: event.fromUser,
              messageBody: event.plaintext,
            );
          }
        }
      });
    });

    // Listen to auth state changes
    ref.listen<AuthStatus>(authProvider, (previous, next) {
      if (next.isAuthenticated && _currentScreen != AppScreen.home) {
        // Load persisted conversations from the message database
        final repo = ref.read(messageRepositoryProvider);
        if (repo != null) {
          ref.read(conversationsProvider.notifier).loadConversations(repo);
        }
        setState(() {
          _currentScreen = AppScreen.home;
        });
      } else if (!next.isAuthenticated && _currentScreen == AppScreen.home) {
        ref.read(conversationsProvider.notifier).clear();
        setState(() {
          _currentScreen = AppScreen.login;
        });
      }
    });

    return MaterialApp(
      title: 'Cryptic',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() => switch (_currentScreen) {
        AppScreen.splash => SplashScreen(
            onInitialized: (needsSetup) {
              setState(() {
                _currentScreen =
                    needsSetup ? AppScreen.enrollment : AppScreen.login;
              });
            },
          ),
        AppScreen.enrollment => EnrollmentFlowScreen(
            onComplete: () async {
              ref.read(enrollmentProvider.notifier).reset();
              await ref.read(authProvider.notifier).checkAuthState();
              if (mounted) {
                setState(() {
                  _loginKey++;
                  _currentScreen = AppScreen.login;
                });
              }
            },
          ),
        AppScreen.login => LoginScreen(
            key: ValueKey(_loginKey),
            onLoginSuccess: () {
              setState(() {
                _currentScreen = AppScreen.home;
              });
            },
            onReenroll: () {
              setState(() {
                _currentScreen = AppScreen.enrollment;
              });
            },
          ),
        AppScreen.home => const UsersScreen(),
      };
}
