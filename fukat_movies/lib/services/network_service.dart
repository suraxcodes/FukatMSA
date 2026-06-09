import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

enum NetworkSpeed { unknown, fast, slow, offline }

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  // Stream to broadcast network speed changes
  final StreamController<NetworkSpeed> _speedController = StreamController<NetworkSpeed>.broadcast();
  Stream<NetworkSpeed> get onSpeedChange => _speedController.stream;

  NetworkSpeed currentSpeed = NetworkSpeed.unknown;
  List<ConnectivityResult> currentConnection = [ConnectivityResult.none];

  void initialize() {
    _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) async {
      currentConnection = result;
      if (result.contains(ConnectivityResult.none)) {
        _updateSpeed(NetworkSpeed.offline);
      } else {
        // We have some connection (WiFi or Mobile), let's test the speed
        await checkNetworkSpeed();
      }
    });
    
    // Initial check
    _connectivity.checkConnectivity().then((result) async {
      currentConnection = result;
      if (result.contains(ConnectivityResult.none)) {
        _updateSpeed(NetworkSpeed.offline);
      } else {
        await checkNetworkSpeed();
      }
    });
  }

  void _updateSpeed(NetworkSpeed speed) {
    if (currentSpeed != speed) {
      currentSpeed = speed;
      _speedController.add(speed);
    }
  }

  Future<void> checkNetworkSpeed() async {
    if (currentConnection.contains(ConnectivityResult.none)) {
      _updateSpeed(NetworkSpeed.offline);
      return;
    }

    try {
      final startTime = DateTime.now();
      // Ping a reliable small payload to measure latency/speed (Google's blank page)
      final response = await http.get(Uri.parse('https://www.google.com/generate_204')).timeout(const Duration(seconds: 5));
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      // If it takes more than 1500ms (1.5s) to get a simple 204 response, the network is likely slow
      if (duration > 1500) {
        _updateSpeed(NetworkSpeed.slow);
      } else {
        _updateSpeed(NetworkSpeed.fast);
      }
    } catch (e) {
      // If it times out or fails, assume slow or offline
      _updateSpeed(NetworkSpeed.slow);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _speedController.close();
  }
}
