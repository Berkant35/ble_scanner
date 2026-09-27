# ble_scanner

Raw BLE advertisement scanner for Flutter (Android + iOS), built for
[BeneathSOS](https://github.com/Berkant35/beneathsos).

Every received advertisement becomes a `ScanSample`: RSSI, company identifier, manufacturer data,
service UUIDs, local name, TX power and a **monotonic** receive timestamp. Samples are buffered
natively and delivered in batches (default 250 ms) so high-rate scans do not flood the platform channel.

```dart
final scanner = BleScanner();
scanner.samples.listen((batch) { /* ... */ });
await scanner.start(); // low-latency, duplicates allowed
```

## Platform notes
- **Android:** one long-running scan (Android blocks >5 scan starts per 30 s; restarts are delayed,
  not dropped). Declares `BLUETOOTH_SCAN` **without** `neverForLocation` — that flag makes Android
  filter some beacon advertisements. Your app must request `BLUETOOTH_SCAN` and location at runtime.
- **iOS:** foreground scanning with `allowDuplicates`. Add `NSBluetoothAlwaysUsageDescription` to
  `Info.plist`. iOS may hide Apple (`0x004C`) advertisements from apps — verify on device.

## Development
Pigeon contract: `pigeons/messages.dart` → `fvm dart run pigeon --input pigeons/messages.dart`.

Licence: Apache-2.0.
