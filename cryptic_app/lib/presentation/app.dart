// lib/presentation/app.dart
//
// Root application widget
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/update/update_prompt.dart';
import '../core/utils/logger.dart';
import '../data/engine/engine_state.dart';
import '../data/engine/incoming_event_handler.dart';
import '../data/services/background_service.dart';
import '../data/services/incoming_share_service.dart';
import '../data/services/notification_service.dart';
import '../data/storage/media_store.dart';
import '../data/storage/preferences/encrypted_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/engine_provider.dart';
import 'providers/enrollment_provider.dart';
import 'providers/incoming_share_provider.dart';
import 'providers/messages_provider.dart';
import 'screens/enrollment/enrollment_flow_screen.dart';
import 'screens/login_screen.dart';
import 'screens/share_target_screen.dart';
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

class _CrypticAppState extends ConsumerState<CrypticApp>
    with WidgetsBindingObserver {
  AppScreen _currentScreen = AppScreen.splash;
  int _loginKey = 0;
  bool _wasBackgrounded = false;

  /// True while the share target picker is open.
  bool _offeringShares = false;

  StreamSubscription<void>? _shareNoticeSubscription;

  /// Lets the startup update check show a dialog with a valid Navigator
  /// context (this State sits above the MaterialApp's own Navigator).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start starts with the app in the foreground: sync the static
    // flag with the current lifecycle state so notifications do not fire
    // while the user is looking at the app (the flag defaults to false and
    // is only updated on lifecycle changes afterwards).
    NotificationService.appResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    // Check GitHub Releases for a newer side-loaded APK once, after first
    // frame so a Navigator/Overlay is available for the prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _navigatorKey.currentContext;
      if (ctx != null) {
        checkAndPromptForUpdate(ctx);
      }
      // Listen for files shared from other apps (cold start and warm start).
      // Subscribe before start() so a notice from the first read is not lost.
      _shareNoticeSubscription = ref
          .read(incomingShareServiceProvider)
          .unsupportedShares
          .listen((_) => _showShareNotice());
      unawaited(ref.read(incomingShareProvider.notifier).start());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shareNoticeSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _wasBackgrounded = true;
        // Background delivery is the point of the foreground service: the
        // shade notification is the primary surface while paused/hidden.
        NotificationService.appResumed = false;
        break;
      case AppLifecycleState.resumed:
        NotificationService.appResumed = true;
        if (_wasBackgrounded) {
          _wasBackgrounded = false;
          final engine = ref.read(authenticatedEngineProvider);
          if (engine != null) {
            unawaited(_evictMediaCache());
            unawaited(engine.reconnectAfterAppResume());
            // The OS can kill the foreground service (Android 15 dataSync
            // runtime cap); restart it on resume when the user wants background
            // delivery. start() no-ops if the service is already running.
            // Only do this with an engine behind it: without a logged-in user
            // the service would just show an empty keep-alive notification.
            unawaited(_restartBackgroundServiceIfNeeded());
          }
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('Building CrypticApp', tag: 'App');

    // Globally persist incoming messages regardless of which screen is open.
    // Without this, messages arriving while the ChatScreen is not mounted
    // (e.g. pending messages delivered on connect) would be lost.
    ref
      // Offer the peer picker when shares arrive while logged in.
      ..listen<List<IncomingShare>>(incomingShareProvider, (previous, next) {
        if (next.isNotEmpty) _scheduleShareOffer();
      })
      ..listen<AsyncValue<EngineEvent>>(engineEventsProvider, (previous, next) {
        next.whenData((event) {
          if (event is MessageReceived || event is FileReceived) {
            final repo = ref.read(messageRepositoryProvider);
            final notifier = ref.read(conversationsProvider.notifier);
            unawaited(handleIncomingEvent(
              event,
              repo: repo,
              addMessage: notifier.addMessage,
              notificationService: NotificationService.instance,
            ));
          }
        });
      })
      // Listen to auth state changes
      ..listen<AuthStatus>(authProvider, (previous, next) {
        if (next.isAuthenticated && _currentScreen != AppScreen.home) {
          // Evict stale media once authenticated at startup/login.
          unawaited(_evictMediaCache());
          // Load persisted conversations from the message database
          final repo = ref.read(messageRepositoryProvider);
          if (repo != null) {
            ref.read(conversationsProvider.notifier).loadConversations(repo);
          }
          // Start the background connection (Android only): ask for the
          // notification permission first, then start the keep-alive service.
          unawaited(_startBackgroundConnection());
          setState(() {
            _currentScreen = AppScreen.home;
          });
          // A share may have arrived before login: offer it now.
          _scheduleShareOffer();
        } else if (!next.isAuthenticated && _currentScreen == AppScreen.home) {
          ref.read(conversationsProvider.notifier).clear();
          unawaited(BackgroundService.instance.stop());
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

  /// Restarts the keep-alive service if the OS killed it (dataSync timeout).
  /// No-op when the user disabled the background connection.
  Future<void> _restartBackgroundServiceIfNeeded() async {
    if (!Platform.isAndroid) return;
    try {
      if (!(await EncryptedPreferences().backgroundConnectionEnabled)) return;
      if (BackgroundService.instance.timedOut) {
        AppLogger.warning(
          'Restarting background service after OS timeout',
          tag: 'App',
        );
      }
      await BackgroundService.instance.start();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Background service restart failed',
        tag: 'App',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Requests the notification permission (Android 13+) and starts the
  /// foreground-service keep-alive when the user enabled background delivery.
  /// Shows the one-time battery-optimization prompt afterwards.
  Future<void> _startBackgroundConnection() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = EncryptedPreferences();
      if (!(await prefs.backgroundConnectionEnabled)) return;

      await NotificationService.instance.requestPermission();
      await BackgroundService.instance.start();

      // One-time battery prompt: without the Doze exemption the background
      // connection gets throttled on many OEMs. The flag is set after the
      // dialog is dismissed so a failed/absent UI can prompt again later.
      final exempt = await BackgroundService.instance.isBatteryExempt;
      final promptShown = await prefs.batteryPromptShown;
      if (!exempt && !promptShown && _navigatorKey.currentContext != null) {
        // Await the dialog so the flag is only set after the user has seen
        // it: if the UI fails to show, the prompt is offered again later.
        await _showBatteryPrompt();
        await prefs.setBatteryPromptShown(true);
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Background connection startup failed',
        tag: 'App',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Explains why the app asks for battery-optimization exemption and opens
  /// the system request dialog. Completes when the dialog is dismissed.
  Future<void> _showBatteryPrompt() {
    final context = _navigatorKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Receive messages in the background'),
        content: const Text(
          'Cryptic keeps an encrypted connection alive so messages arrive '
          'while the app is closed. Android may pause this connection to save '
          'battery. Allow Cryptic to run unrestricted for reliable delivery - '
          'you can change this later in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(BackgroundService.instance.requestBatteryExemption());
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  /// Tells the user that text or links in a share were not taken.
  void _showShareNotice() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Text and link shares are not supported')),
    );
  }

  /// Opens the share target picker after the current frame, if needed.
  void _scheduleShareOffer() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerPendingShares());
  }

  /// Opens the peer picker when shares are waiting and the user is logged in.
  /// Pending shares stay in the provider until the user picks a peer.
  void _offerPendingShares() {
    if (!mounted || _offeringShares) return;
    if (_currentScreen != AppScreen.home) return;
    if (!ref.read(authProvider).isAuthenticated) return;
    if (ref.read(incomingShareProvider).isEmpty) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    _offeringShares = true;
    unawaited(
      navigator
          .push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const ShareTargetScreen(),
            ),
          )
          .whenComplete(() => _offeringShares = false),
    );
  }

  Future<void> _evictMediaCache() async {
    try {
      final repository = ref.read(messageRepositoryProvider);
      final protectedPaths = await repository?.getRecentMediaPaths() ?? {};
      final removed = await MediaStore().evict(protectedPaths: protectedPaths);
      if (removed.isNotEmpty) await repository?.clearLocalPaths(removed);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Media cache eviction failed',
        tag: 'App',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
