import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'services/remote_config_service.dart';
import 'services/supabase_auth_service.dart';
import 'screens/home_screen.dart';

import 'package:http/http.dart' as http;
import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';

void main() {
  if (Platform.isAndroid) {
    http.runWithClient(
      _mainAsync,
      () => CronetClient.defaultCronetEngine(),
    );
  } else if (Platform.isIOS || Platform.isMacOS) {
    http.runWithClient(
      _mainAsync,
      () => CupertinoClient.defaultSessionConfiguration(),
    );
  } else {
    _mainAsync();
  }
}

Future<void> _mainAsync() async {
  // 1. Ensure structural widget engine bindings are completely ready
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize window manager only on desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      fullScreen: true,
      center: true,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
    });
  }
  MediaKit.ensureInitialized();

  bool initializationSuccess = false;

  try {
    // 2. Load environmental variable configurations from assets folder
    await dotenv.load(fileName: "assets/.env");

    // 3. Initialize Hive core storage paths FIRST
    // Must be done before RemoteConfigService because it uses Hive
    await Hive.initFlutter();

    // 4. Fetch server-side network values before initializing Supabase
    // Wrapped in a sub-try block so network issues don't crash local database access
    try {
      await RemoteConfigService.initializeConfig();
    } catch (networkError) {
      print("⚠️ Remote Config failed to load (Using cached/default providers): $networkError");
    }

    // 5. Initialize Supabase Client
    final supabaseUrl = RemoteConfigService.remoteEnv['SUPABASE_URL'] ?? dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = RemoteConfigService.remoteEnv['SUPABASE_ANON_KEY'] ?? dotenv.env['SUPABASE_ANON_KEY'];
    if (supabaseUrl != null && supabaseAnonKey != null && supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } else {
      throw Exception('Supabase credentials are empty or missing in remote config and .env file.');
    }

    // 6. HARD BLOCK: Concurrently open all local database box files on disk storage.
    print("📦 Opening critical local databases...");
    await Future.wait([
      Hive.openBox('watchlistBox'),
      Hive.openBox('continueWatchingBox'),
      Hive.openBox('customRepoBox'),
    ]);
    print("📦 Databases active and available.");

    initializationSuccess = true;

  } catch (e) {
    print("🚨 Fatal Core Startup Exception: $e");
    initializationSuccess = false;
  }

  // 7. Launch the UI tree with the initialization status flag passed in
  runApp(MyApp(isInitializedSuccessfully: initializationSuccess));
}

class MyApp extends StatelessWidget {
  final bool isInitializedSuccessfully;
  
  const MyApp({Key? key, required this.isInitializedSuccessfully}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fukat MSA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF141414), // Netflix deep dark configuration
        focusColor: Colors.white30,
        highlightColor: Colors.redAccent.withOpacity(0.2),
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      // If critical local storage/Supabase setups failed, show an explicit error screen instead of crashing
      home: isInitializedSuccessfully 
          ? const AuthWrapper() 
          : const Scaffold(
              backgroundColor: Color(0xFF141414),
              body: Center(
                child: Text(
                  'Fatal Initialization Error.\nPlease restart the app or check your configuration.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
              ),
            ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // HomeScreen will manage its own state (login popup)
    return HomeScreen();
  }
}