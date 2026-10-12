package org.beneathsos.ble_scanner

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Raw BLE scanner. Keeps one long-running scan (Android allows at most 5 scan starts per 30 s),
 * buffers results and delivers them to Dart in batches. Also advertises one service (victim mode).
 */
class BleScannerPlugin : FlutterPlugin, BleScannerHostApi {
  private lateinit var context: Context
  private lateinit var flutterApi: BleScannerFlutterApi
  private val main = Handler(Looper.getMainLooper())
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private val buffer = ArrayList<ScanSample>()
  private val startTimes = ArrayDeque<Long>()
  private var batchIntervalMs = 250L
  private var scanning = false
  private var pendingStart: Runnable? = null
  private var advertising: AdvertiseCallback? = null

  private val adapter: BluetoothAdapter?
    get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter

  private val flushTask = object : Runnable {
    override fun run() {
      flush()
      if (scanning) main.postDelayed(this, batchIntervalMs)
    }
  }

  private val stateReceiver = object : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
      if (intent.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
      emit { flutterApi.onAdapterStateChanged(adapterState()) }
    }
  }

  private val callback = object : ScanCallback() {
    override fun onScanResult(callbackType: Int, result: ScanResult) {
      synchronized(buffer) { buffer.add(result.toSample()) }
    }

    override fun onBatchScanResults(results: MutableList<ScanResult>) {
      synchronized(buffer) { results.forEach { buffer.add(it.toSample()) } }
    }

    override fun onScanFailed(errorCode: Int) {
      scanning = false
      emit { flutterApi.onScanError(errorCode.toLong(), "scan failed: $errorCode") }
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    flutterApi = BleScannerFlutterApi(binding.binaryMessenger)
    BleScannerHostApi.setUp(binding.binaryMessenger, this)
    context.registerReceiver(stateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    stopScan()
    stopAdvertising()
    context.unregisterReceiver(stateReceiver)
    BleScannerHostApi.setUp(binding.binaryMessenger, null)
    scope.cancel()
  }

  /** Delivers a message to Dart; a detached engine must never crash the scanner. */
  private fun emit(block: suspend () -> Unit) {
    scope.launch {
      try {
        block()
      } catch (e: FlutterError) {
        Log.w(TAG, "Dart side unavailable: ${e.message}")
      }
    }
  }

  override fun adapterState(): AdapterState {
    val a = adapter ?: return AdapterState.UNSUPPORTED
    return try {
      if (a.isEnabled) AdapterState.POWERED_ON else AdapterState.POWERED_OFF
    } catch (_: SecurityException) {
      AdapterState.UNAUTHORIZED
    }
  }

  override fun capabilities(): ScannerCapabilities {
    val a = adapter
    val o = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
    return ScannerCapabilities(
      platform = "android",
      codedPhySupported = o && a?.isLeCodedPhySupported == true,
      extendedAdvertisingSupported = o && a?.isLeExtendedAdvertisingSupported == true,
      advertisingSupported = a?.bluetoothLeAdvertiser != null,
    )
  }

  @SuppressLint("MissingPermission")
  override fun startScan(config: ScanConfig) {
    stopScan()
    batchIntervalMs = config.batchIntervalMs.coerceAtLeast(50)
    val delay = throttleDelayMs()
    val scanner = adapter?.bluetoothLeScanner
      ?: throw FlutterError("unavailable", "Bluetooth LE scanner unavailable (adapter off?)", null)
    val settings = ScanSettings.Builder()
      .setScanMode(config.mode.toAndroid())
      .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
      .setReportDelay(0)
      .apply {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          setLegacy(false)
          setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
        }
      }
      .build()
    val filters = config.serviceUuids.map {
      ScanFilter.Builder().setServiceUuid(ParcelUuid.fromString(it)).build()
    }
    val start = Runnable {
      pendingStart = null
      try {
        scanner.startScan(filters, settings, callback)
        startTimes.addLast(SystemClock.elapsedRealtime())
        scanning = true
        main.postDelayed(flushTask, batchIntervalMs)
      } catch (e: SecurityException) {
        emit { flutterApi.onScanError(-1, "unauthorized: ${e.message}") }
      }
    }
    if (delay == 0L) start.run() else { pendingStart = start; main.postDelayed(start, delay) }
  }

  @SuppressLint("MissingPermission")
  override fun stopScan() {
    pendingStart?.let { main.removeCallbacks(it) }
    pendingStart = null
    if (!scanning) return
    scanning = false
    main.removeCallbacks(flushTask)
    try {
      adapter?.bluetoothLeScanner?.stopScan(callback)
    } catch (_: SecurityException) {
      // Permission revoked while scanning; nothing left to stop.
    }
    flush()
  }

  /**
   * Advertises [AdvertiseConfig.serviceUuid] in the advert and the service data in the scan response
   * (legacy, low latency, high power, not connectable, no timeout). A new call replaces the payload.
   * Android cannot advertise a custom local name, so it is ignored.
   */
  @SuppressLint("MissingPermission")
  override fun startAdvertising(config: AdvertiseConfig) {
    stopAdvertising()
    val advertiser = adapter?.bluetoothLeAdvertiser
      ?: throw FlutterError("unavailable", "Bluetooth LE advertising unavailable (adapter off?)", null)
    val uuid = ParcelUuid.fromString(config.serviceUuid)
    val settings = AdvertiseSettings.Builder()
      .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
      .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
      .setConnectable(false)
      .setTimeout(0)
      .build()
    val advert = AdvertiseData.Builder()
      .setIncludeDeviceName(false)
      .setIncludeTxPowerLevel(false)
      .addServiceUuid(uuid)
      .build()
    val response = AdvertiseData.Builder()
      .setIncludeDeviceName(false)
      .setIncludeTxPowerLevel(false)
      .apply { config.serviceData?.let { addServiceData(uuid, it) } }
      .build()
    val callback = object : AdvertiseCallback() {
      override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
        emit { flutterApi.onAdvertiseStarted() }
      }

      override fun onStartFailure(errorCode: Int) {
        if (advertising === this) advertising = null
        emit { flutterApi.onAdvertiseError(errorCode.toLong(), "advertise failed: $errorCode") }
      }
    }
    try {
      advertiser.startAdvertising(settings, advert, response, callback)
      advertising = callback
    } catch (e: SecurityException) {
      emit { flutterApi.onAdvertiseError(-1, "unauthorized: ${e.message}") }
    }
  }

  @SuppressLint("MissingPermission")
  override fun stopAdvertising() {
    val callback = advertising ?: return
    advertising = null
    try {
      adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
    } catch (_: SecurityException) {
      // Permission revoked while advertising; nothing left to stop.
    }
  }

  /** Android blocks apps that start more than 5 scans in 30 s; wait instead of failing silently. */
  private fun throttleDelayMs(): Long {
    val now = SystemClock.elapsedRealtime()
    while (startTimes.isNotEmpty() && now - startTimes.first() > WINDOW_MS) startTimes.removeFirst()
    return if (startTimes.size < MAX_STARTS) 0L else WINDOW_MS - (now - startTimes.first()) + 100
  }

  private fun flush() {
    val batch: List<ScanSample>
    synchronized(buffer) {
      if (buffer.isEmpty()) return
      batch = ArrayList(buffer)
      buffer.clear()
    }
    emit { flutterApi.onSamples(batch) }
  }

  private fun ScanResult.toSample(): ScanSample {
    val record = scanRecord
    val mfr = record?.manufacturerSpecificData
    val companyId = if (mfr != null && mfr.size() > 0) mfr.keyAt(0) else null
    val tx = when {
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && txPower != ScanResult.TX_POWER_NOT_PRESENT -> txPower
      record != null && record.txPowerLevel != Int.MIN_VALUE -> record.txPowerLevel
      else -> null
    }
    return ScanSample(
      peripheralKey = device.address,
      rssi = rssi.toLong(),
      txPower = tx?.toLong(),
      companyId = companyId?.toLong(),
      manufacturerData = companyId?.let { mfr?.get(it) },
      serviceUuids = record?.serviceUuids?.map { it.toString() } ?: emptyList(),
      localName = record?.deviceName,
      serviceData = record?.serviceData?.entries?.associate { (k, v) -> k.toString() to v },
      connectable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) isConnectable else null,
      monotonicNanos = timestampNanos,
      wallClockMillis = System.currentTimeMillis(),
    )
  }

  private fun ScanMode.toAndroid(): Int = when (this) {
    ScanMode.LOW_POWER -> ScanSettings.SCAN_MODE_LOW_POWER
    ScanMode.BALANCED -> ScanSettings.SCAN_MODE_BALANCED
    ScanMode.LOW_LATENCY -> ScanSettings.SCAN_MODE_LOW_LATENCY
  }

  private companion object {
    const val MAX_STARTS = 5
    const val WINDOW_MS = 30_000L
    const val TAG = "BleScanner"
  }
}
