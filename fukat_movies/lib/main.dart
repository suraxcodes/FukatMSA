import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'services/remote_config_service.dart';
import 'services/supabase_auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';

Future<void> main() async {
  // 1. Ensure structural widget engine bindings are completely ready
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  bool initializationSuccess = false;

  try {
    // 2. Load environmental variable configurations from assets folder
    await dotenv.load(fileName: "assets/.env");

    // 3. Initialize Supabase Client
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    if (supabaseUrl != null && supabaseAnonKey != null && supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } else {
      throw Exception('Supabase credentials are empty or missing in .env file.');
    }

    // 4. Initialize Hive core storage paths
    await Hive.initFlutter();

    // 5. HARD BLOCK: Concurrently open all local database box files on disk storage.
    print("📦 Opening critical local databases...");
    await Future.wait([
      Hive.openBox('watchlistBox'),
      Hive.openBox('continueWatchingBox'),
      Hive.openBox('customRepoBox'),
    ]);
    print("📦 Databases active and available.");

    // 6. Fetch server-side network values before the home screen mounts
    // Wrapped in a sub-try block so network issues don't crash local database access
    try {
      await RemoteConfigService.initializeConfig();
    } catch (networkError) {
      print("⚠️ Remote Config failed to load (Using cached/default providers): $networkError");
    }

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
    return StreamBuilder<AuthState>(
      stream: SupabaseAuthService.authStateChanges,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF141414),
            body: Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            ),
          );
        }

        final session = snapshot.data?.session;
        if (session != null) {
          return HomeScreen();
        }
        
        return const AuthScreen();
      },
    );
  }
}