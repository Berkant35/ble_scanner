# ble_scanner

[![CI](https://github.com/Berkant35/ble_scanner/actions/workflows/ci.yml/badge.svg)](https://github.com/Berkant35/ble_scanner/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Raw BLE advertisement scanner — and a one-service advertiser — for Flutter (Android + iOS), built for
[BeneathSOS](https://github.com/Berkant35/beneathsos).

Every received advertisement becomes a `ScanSample`: RSSI, company identifier, manufacturer data,
service UUIDs, service data, local name, TX power and a **monotonic** receive timestamp. Samples are buffered
natively and delivered in batches (default 250 ms) so high-rate scans do not flood the platform channel.

```dart
final scanner = BleScanner();
scanner.samples.listen((batch) { /* ... */ });
await scanner.start(); // low-latency, duplicates allowed

// Advertise one service (BeneathSOS victim mode). Calling it again replaces the payload.
await scanner.startAdvertising(
  serviceUuid: '06ad86ef-1e8c-47b4-9c65-c526d5e31581',
  localName: 'SOS-1A2B', // iOS only
  serviceData: Uint8List.fromList([1, 0x1a, 0x2b, 80, 3]), // Android only, ≤ 11 bytes
);
scanner.advertiseErrors.listen((e) { /* ... */ });
```

## Platform notes
- **Android:** one long-running scan (Android blocks >5 scan starts per 30 s; restarts are delayed,
  not dropped). Declares `BLUETOOTH_SCAN` **without** `neverForLocation` — that flag makes Android
  filter some beacon advertisements. Your app must request `BLUETOOTH_SCAN` and location at runtime.
  Advertising: legacy, low latency, high power, not connectable; service UUID in the advert, service
  data in the scan response; declares `BLUETOOTH_ADVERTISE` (request it at runtime). Android cannot
  advertise a custom local name.
- **iOS:** foreground scanning with `allowDuplicates`. Add `NSBluetoothAlwaysUsageDescription` to
  `Info.plist`. iOS may hide Apple (`0x004C`) advertisements from apps — verify on device.
  Advertising: service UUID + local name only (no service data on iOS); in the background the UUID
  moves to the overflow area (add `bluetooth-peripheral` to `UIBackgroundModes`) and only iOS scanners
  looking for it see it.

## Development
Pigeon contract: `pigeons/messages.dart` → `fvm dart run pigeon --input pigeons/messages.dart`.

Licence: Apache-2.0.
