import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Network Connectivity Service detecting online and offline state transitions.
class NetworkService {
  static NetworkService? _instance;
  final Connectivity _connectivity;
  final StreamController<bool> _connectivityStreamController = StreamController<bool>.broadcast();
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  NetworkService._({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  static NetworkService get instance {
    _instance ??= NetworkService._();
    return _instance!;
  }

  /// Sets custom connectivity for unit testing
  static void setMockInstance(NetworkService service) {
    _instance = service;
  }

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _connectivityStreamController.stream;

  void _init() {
    // Initial check
    _connectivity.checkConnectivity().then(_updateStatus);

    // Listen to network changes
    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final bool online = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      _connectivityStreamController.add(_isOnline);
    }
  }

  /// Manually checks current network connectivity status
  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      return _isOnline;
    } catch (_) {
      return _isOnline;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _connectivityStreamController.close();
  }
}

