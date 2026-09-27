import 'dart:async';

import 'package:ble_scanner/src/messages.g.dart';

/// Error reported by the native scanner (for example Android scan failure codes).
final class BleScanError implements Exception {
  /// Creates an error with the platform [code] and a human readable [message].
  const BleScanError(this.code, this.message);

  /// Platform error code (Android `ScanCallback` codes, `-1` for permission problems).
  final int code;

  /// Description from the platform.
  final String message;

  @override
  String toString() => 'BleScanError($code, $message)';
}

/// Entry point of the plugin. Create one instance per app and [dispose] it when done.
class BleScanner implements BleScannerFlutterApi {
  /// Creates a scanner. [hostApi] can be replaced in tests.
  BleScanner({BleScannerHostApi? hostApi})
    : _host = hostApi ?? BleScannerHostApi() {
    BleScannerFlutterApi.setUp(this);
  }

  final BleScannerHostApi _host;
  final _samples = StreamController<List<ScanSample>>.broadcast();
  final _adapter = StreamController<AdapterState>.broadcast();
  final _errors = StreamController<BleScanError>.broadcast();

  /// Batches of received advertisements, in arrival order.
  Stream<List<ScanSample>> get samples => _samples.stream;

  /// Adapter state changes (Bluetooth turned on/off, permission changes on iOS).
  Stream<AdapterState> get adapterStates => _adapter.stream;

  /// Scan failures reported asynchronously by the platform.
  Stream<BleScanError> get errors => _errors.stream;

  /// Current adapter state. On iOS the first call may show the Bluetooth permission prompt.
  Future<AdapterState> adapterState() => _host.adapterState();

  /// What this device supports.
  Future<ScannerCapabilities> capabilities() => _host.capabilities();

  /// Starts (or restarts) scanning. Defaults suit RSSI measurements.
  Future<void> start({
    ScanMode mode = ScanMode.lowLatency,
    List<String> serviceUuids = const [],
    Duration batchInterval = const Duration(milliseconds: 250),
  }) => _host.startScan(
    ScanConfig(
      mode: mode,
      serviceUuids: serviceUuids,
      batchIntervalMs: batchInterval.inMilliseconds,
    ),
  );

  /// Stops scanning and flushes buffered samples.
  Future<void> stop() => _host.stopScan();

  /// Releases the Dart side. The instance cannot be used afterwards.
  Future<void> dispose() async {
    BleScannerFlutterApi.setUp(null);
    await Future.wait([_samples.close(), _adapter.close(), _errors.close()]);
  }

  @override
  void onSamples(List<ScanSample> samples) => _samples.add(samples);

  @override
  void onAdapterStateChanged(AdapterState state) => _adapter.add(state);

  @override
  void onScanError(int code, String message) =>
      _errors.add(BleScanError(code, message));
}
