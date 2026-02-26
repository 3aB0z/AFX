import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'pages/auth_page.dart';
import 'pages/chat_page.dart';
import 'pages/requests_page.dart';
import 'pages/rejected_page.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/theme_service.dart';
import 'services/error_service.dart';
import 'config.dart';
import 'dart:async';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[BACKGROUND] 🌙 Message received: ${message.messageId}');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Delegate to NotificationService for unified grouping/storage logic
    await NotificationService.onBackgroundMessage(message);

    // Simple success log
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'bg_log_status',
      'Unified notification handled at ${DateTime.now()}',
    );
  } catch (e) {
    debugPrint('[BACKGROUND] ❌ Error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('[MAIN] ✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('[MAIN] ⚠️ Firebase initialization error: $e');
  }

  // Load environment variables from .env file
  try {
    await dotenv.load(fileName: ".env");
    debugPrint('[MAIN] .env file loaded successfully');
  } catch (e) {
    debugPrint('[MAIN] Warning: Could not load .env file: $e');
  }

  // Initialize theme service
  try {
    await ThemeService.initialize();
    debugPrint('[MAIN] ✅ Theme service initialized');
  } catch (e) {
    debugPrint('[MAIN] ⚠️ Theme service initialization error: $e');
  }

  runApp(const AFXApp());
}

class AFXApp extends StatefulWidget {
  const AFXApp({super.key});

  @override
  State<AFXApp> createState() => _AFXAppState();
}

class _AFXAppState extends State<AFXApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.isForeground = true;
    _checkBackgroundLogs();
  }

  void _checkBackgroundLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final start = prefs.getString('bg_log_start');
      final msgId = prefs.getString('bg_log_msg_id');
      final step = prefs.getString('bg_log_step');
      final status = prefs.getString('bg_log_status');
      final error = prefs.getString('bg_log_error');

      if (start != null || error != null) {
        debugPrint(
          '\n================ [BACKGROUND DIAGNOSTICS] ================',
        );
        debugPrint('Start Time: $start');
        debugPrint('Message ID: $msgId');
        debugPrint('Last Step:  $step');
        debugPrint('Status:     $status');
        debugPrint('Error:      $error');
        debugPrint(
          '==========================================================\n',
        );

        // Clear logs
        await prefs.remove('bg_log_start');
        await prefs.remove('bg_log_msg_id');
        await prefs.remove('bg_log_step');
        await prefs.remove('bg_log_status');
        await prefs.remove('bg_log_error');
      }
    } catch (e) {
      debugPrint('[DIAGNOSTICS] Failed to check logs: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[LIFECYCLE] App state changed: $state');

    // Update foreground flag in NotificationService
    if (state == AppLifecycleState.resumed) {
      NotificationService.isForeground = true;
    } else {
      NotificationService.isForeground = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, mode, child) {
        return MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          scaffoldMessengerKey: ErrorService.messengerKey,
          title: 'AFX',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData.light(useMaterial3: true).copyWith(
            primaryColor: Config.primaryColor,
            scaffoldBackgroundColor: Config.bgLight,
            appBarTheme: const AppBarTheme(
              backgroundColor: Config.bgLight,
              foregroundColor: Config.textPrimaryLight,
              elevation: 0,
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Config.textPrimaryLight),
              bodyMedium: TextStyle(color: Config.textPrimaryLight),
            ),
            textSelectionTheme: TextSelectionThemeData(
              selectionColor: Config.primaryColor.withAlpha(76),
              cursorColor: Config.primaryColor,
              selectionHandleColor: Config.primaryColor,
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Config.primaryColor,
              brightness: Brightness.light,
              surface: Config.bgLight,
            ),
            progressIndicatorTheme: const ProgressIndicatorThemeData(
              color: Config.primaryColor,
            ),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            primaryColor: Config.primaryColor,
            scaffoldBackgroundColor: Config.bgDark,
            appBarTheme: const AppBarTheme(
              backgroundColor: Config.bgDark,
              foregroundColor: Config.textPrimaryDark,
              elevation: 0,
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Config.textPrimaryDark),
              bodyMedium: TextStyle(color: Config.textPrimaryDark),
            ),
            textSelectionTheme: TextSelectionThemeData(
              selectionColor: Config.primaryColor.withAlpha(76),
              cursorColor: Config.primaryColor,
              selectionHandleColor: Config.primaryColor,
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Config.primaryColor,
              brightness: Brightness.dark,
              surface: Config.bgDark,
            ),
            progressIndicatorTheme: const ProgressIndicatorThemeData(
              color: Config.primaryColor,
            ),
          ),
          // Use StreamBuilder to handle auth state changes automatically
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final user = snapshot.data;
              if (user == null) {
                return const AuthPage();
              }

              // If user is logged in, we listen to their Firestore data in realtime
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseService.getUserDataStream(user.uid),
                builder: (context, firestoreSnapshot) {
                  if (firestoreSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final userData = firestoreSnapshot.data?.data();

                  if (userData == null) {
                    return const AuthPage(); // Fallback if data deleted
                  }

                  final status = (userData['status'] ?? 'pending')
                      .toString()
                      .toLowerCase();

                  if (status == 'rejected') {
                    return RejectedPage(
                      rejectedAt: (userData['rejected_at'] as Timestamp?)
                          ?.toDate(),
                    );
                  }

                  if (status == 'verified') {
                    // Clear device rejection if account is now verified
                    FirebaseService.clearDeviceRejection();

                    // Save config locally for next cold start
                    final canSend = userData['can_send_messages'] == true;
                    final role = userData['role'] ?? 'user';
                    FirebaseService.saveUserConfig(
                      canSendMessages: canSend,
                      role: role,
                    );

                    // Update notification subscriptions
                    NotificationService.updateSubscriptions(role, status);

                    return ChatPage(
                      userId: user.uid,
                      userName: userData['name'] ?? 'User',
                      userEmail: user.email ?? '',
                      userRole: role,
                      canSendMessages: canSend, // Pass directly
                    );
                  }

                  if (status == 'pending') {
                    return const AuthPage(initialIndex: 1);
                  }

                  return const AuthPage(initialIndex: 1);
                },
              );
            },
          ),
          routes: {'/requests': (context) => const RequestsPage()},
        );
      },
    );
  }
}
