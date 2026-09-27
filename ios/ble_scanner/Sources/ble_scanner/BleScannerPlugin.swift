import CoreBluetooth
import Flutter
import Foundation

/// Raw BLE scanner for iOS. Foreground scanning with duplicates allowed so every received
/// advertisement produces an RSSI sample. Samples are buffered and delivered in batches.
public class BleScannerPlugin: NSObject, FlutterPlugin, BleScannerHostApi, CBCentralManagerDelegate {
  private let flutterApi: BleScannerFlutterApi
  private var central: CBCentralManager?
  private var pendingConfig: ScanConfig?
  private var buffer: [ScanSample] = []
  private var flushTimer: Timer?

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = BleScannerFlutterApi(binaryMessenger: messenger)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BleScannerPlugin(messenger: registrar.messenger())
    BleScannerHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }

  /// Created lazily: instantiating CBCentralManager triggers the Bluetooth permission prompt.
  private func manager() -> CBCentralManager {
    if let central { return central }
    let created = CBCentralManager(
      delegate: self, queue: nil,
      options: [CBCentralManagerOptionShowPowerAlertKey: false])
    central = created
    return created
  }

  // MARK: BleScannerHostApi

  func adapterState() throws -> AdapterState {
    Self.map(manager().state)
  }

  func capabilities() throws -> ScannerCapabilities {
    // CoreBluetooth exposes neither PHY selection nor extended advertising to apps.
    ScannerCapabilities(platform: "ios", codedPhySupported: false, extendedAdvertisingSupported: false)
  }

  func startScan(config: ScanConfig) throws {
    stopScan()
    let central = manager()
    guard central.state == .poweredOn else {
      pendingConfig = config  // started from centralManagerDidUpdateState
      return
    }
    begin(config, on: central)
  }

  func stopScan() {
    pendingConfig = nil
    central?.stopScan()
    flushTimer?.invalidate()
    flushTimer = nil
    flush()
  }

  private func begin(_ config: ScanConfig, on central: CBCentralManager) {
    let services = config.serviceUuids.isEmpty ? nil : config.serviceUuids.map { CBUUID(string: $0) }
    central.scanForPeripherals(
      withServices: services,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    let interval = max(Double(config.batchIntervalMs), 50) / 1000
    flushTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.flush()
    }
  }

  // MARK: CBCentralManagerDelegate

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = Self.map(central.state)
    Task { @MainActor in try? await flutterApi.onAdapterStateChanged(state: state) }
    if central.state == .poweredOn, let config = pendingConfig {
      pendingConfig = nil
      begin(config, on: central)
    }
  }

  public func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let rssi = RSSI.intValue
    guard rssi != 127 else { return }  // 127 = RSSI unavailable

    var companyId: Int64?
    var payload: FlutterStandardTypedData?
    if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
      companyId = Int64(data[data.startIndex]) | (Int64(data[data.startIndex + 1]) << 8)
      payload = FlutterStandardTypedData(bytes: data.dropFirst(2))
    }
    var uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    uuids += (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []

    buffer.append(
      ScanSample(
        peripheralKey: peripheral.identifier.uuidString,
        rssi: Int64(rssi),
        txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.int64Value,
        companyId: companyId,
        manufacturerData: payload,
        serviceUuids: uuids.map { $0.uuidString },
        localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
        connectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue,
        monotonicNanos: Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)),
        wallClockMillis: Int64(Date().timeIntervalSince1970 * 1000)))
  }

  // MARK: Helpers

  private func flush() {
    guard !buffer.isEmpty else { return }
    let batch = buffer
    buffer.removeAll(keepingCapacity: true)
    Task { @MainActor in try? await flutterApi.onSamples(samples: batch) }
  }

  private static func map(_ state: CBManagerState) -> AdapterState {
    switch state {
    case .poweredOn: return .poweredOn
    case .poweredOff: return .poweredOff
    case .unauthorized: return .unauthorized
    case .unsupported: return .unsupported
    case .resetting, .unknown: return .unknown
    @unknown default: return .unknown
    }
  }
}
