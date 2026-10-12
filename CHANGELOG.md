## 0.2.0
- Advertising: `startAdvertising` (service UUID; service data on Android, local name on iOS; payload
  checked against a legacy packet), `stopAdvertising`, `advertiseStarted` / `advertiseErrors` streams,
  `ScannerCapabilities.advertisingSupported`. Android declares `BLUETOOTH_ADVERTISE`.
- `ScanSample.serviceData` (service UUID → bytes) on both platforms.

## 0.1.0
- Initial release: batched raw BLE scanning (Android `BluetoothLeScanner`, iOS `CoreBluetooth`),
  adapter state stream, scan error stream, capabilities.
