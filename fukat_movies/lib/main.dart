import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/remote_config_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load environment variables securely
  await dotenv.load(fileName: "assets/.env");
  
  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox('watchlistBox');
  await Hive.openBox('continueWatchingBox');
  
  // Fetch dynamic providers before app starts
  await RemoteConfigService.initializeConfig();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fukat MSA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: Color(0xFF141414), // Netflix dark
      ),
      home: HomeScreen(),
    );
  }
}

