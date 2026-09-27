/// Raw BLE advertisement scanner for Android and iOS.
///
/// Every received advertisement becomes a [ScanSample] with RSSI, optional manufacturer data and a
/// monotonic timestamp. Samples are delivered in batches through [BleScanner.samples].
library;

export 'src/ble_scanner.dart';
export 'src/company_ids.dart';
export 'src/messages.g.dart'
    show AdapterState, ScanConfig, ScanMode, ScanSample, ScannerCapabilities;
