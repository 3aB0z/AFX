import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/auth_page.dart';
import 'pages/chat_page.dart';
import 'pages/requests_page.dart';
import 'auth.dart';
import 'config.dart';
import 'services/notification_service.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  try {
    await dotenv.load(fileName: ".env");
    debugPrint('[MAIN] .env file loaded successfully');
    debugPrint('[MAIN] Environment: ${Config.environment}');
    debugPrint('[MAIN] Is Production: ${Config.isProduction}');
    debugPrint('[MAIN] Is Development: ${Config.isDevelopment}');
    debugPrint(
      '[MAIN] Service role key configured: ${Config.supabaseServiceRoleKey.isNotEmpty}',
    );
  } catch (e) {
    debugPrint('[MAIN] Warning: Could not load .env file: $e');
  }

  // Initialize Supabase using values from config (which reads from .env)
  try {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      anonKey: Config.supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint(
          '[MAIN] Supabase initialization timed out - check your credentials',
        );
        throw Exception('Supabase initialization timeout');
      },
    );
    debugPrint('[MAIN] Supabase initialized successfully');
    debugPrint(
      '[MAIN] Service role key configured: ${Config.supabaseServiceRoleKey.isNotEmpty}',
    );
  } catch (e) {
    debugPrint('[MAIN] Supabase init error: $e - using app in demo mode');
  }

  // Initialize notification service
  try {
    await NotificationService.initialize();
    debugPrint('[MAIN] ✅ Notification service initialized');
  } catch (e) {
    debugPrint('[MAIN] ⚠️ Notification service initialization error: $e');
  }

  runApp(AFXApp());
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
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('[LIFECYCLE] ✅ App RESUMED (in foreground)');
        NotificationService.isForeground = true;
        break;
      case AppLifecycleState.paused:
        debugPrint('[LIFECYCLE] ⏸️ App PAUSED (moved to background)');
        NotificationService.isForeground = false;
        break;
      case AppLifecycleState.detached:
        debugPrint('[LIFECYCLE] 🚫 App DETACHED (closing)');
        NotificationService.isForeground = false;
        break;
      case AppLifecycleState.hidden:
        debugPrint('[LIFECYCLE] 🔒 App HIDDEN');
        // Hidden usually means background on mobile, but check platform behavior if needed
        NotificationService.isForeground = false;
        break;
      case AppLifecycleState.inactive:
        debugPrint('[LIFECYCLE] ⚪ App INACTIVE');
        // Inactive can happen during potential transitions or when notification shade is down. 
        // For strict background requirements, inactive might still be considered "foreground-ish" 
        // or background depending on preference. Often inactive means "not interactable but visible".
        // Let's treat it as background for notifications if user wants "only when background".
        // Actually, on generic phone calls it might be inactive. 
        // Let's set it to false (background) to be safe, so notifications show up if user receives a call.
        NotificationService.isForeground = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AFX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true).copyWith(
        primaryColor: Config.primaryColor,
        appBarTheme: AppBarTheme(
          backgroundColor: Config.primaryColor,
          foregroundColor: Config.textLight,
        ),
        scaffoldBackgroundColor: Config.background,
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: Config.primaryColor.withAlpha(76),
          cursorColor: Config.primaryColor,
          selectionHandleColor: Config.primaryColor,
        ),
      ),
      home: const Splash(),
      routes: {
        '/requests': (context) =>
            const RequestsPage(userId: 0, userName: '', userEmail: ''),
      },
    );
  }
}

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _decide();
  }

  Future<void> _requestNotificationPermission() async {
    try {
      debugPrint('[MAIN] 🔔 Checking notification permissions...');

      // Check if permission is already granted
      final isGranted =
          await NotificationService.isNotificationPermissionGranted();

      if (isGranted) {
        debugPrint('[MAIN] ✅ Notification permission already granted');
      } else {
        debugPrint('[MAIN] 🔔 Requesting notification permission...');
        // Request permission if not granted
        await NotificationService.requestNotificationPermission();
      }
    } catch (e) {
      debugPrint('[MAIN] ⚠️ Error handling notification permission: $e');
    }
  }

  Future<void> _decide() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final login = await Auth.getLogin();
    if (!mounted) return;
    if (login == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
      );
      return;
    }
    final role = login['role'] as String?;
    final id = login['id'];
    final name = login['name'] as String? ?? '';
    final email = login['email'] as String? ?? '';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          userId: id as int,
          userName: name,
          userEmail: email,
          userRole: role ?? 'user',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Config.background,
      body: Center(
        child: CircularProgressIndicator(
          color: Config.primaryColor,
          strokeWidth: 3,
        ),
      ),
    );
  }
}
