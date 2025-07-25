package com.example.school_guardian_mobile_ble

import android.bluetooth.BluetoothAdapter
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import android.content.Intent
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var permissionsResult: MethodChannel.Result? = null

    private val CHANNEL = "ble_advertiser"
    private val TAG = "BLE_ADVERTISER"
    private val REQUEST_PERMISSIONS = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val userId = (call.argument<Int>("userId") ?: 3)
                    startBleAdvertising(userId)
                    result.success(null)
                }
                "stopAdvertising" -> {
                    stopBleAdvertising()
                    result.success(null)
                }
                "isBluetoothOn" -> {
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    result.success(adapter != null && adapter.isEnabled)
                }
                "requestEnableBluetooth" -> {
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    if (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    } else {
                        result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission not granted", null)
                    }
                }
                "checkNativePermissions" -> {
                    val permissions = mapOf(
                        "BLUETOOTH_SCAN" to (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED),
                        "BLUETOOTH_CONNECT" to (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED),
                        "BLUETOOTH_ADVERTISE" to (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED),
                        "ACCESS_FINE_LOCATION" to (ActivityCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
                    )
                    result.success(permissions)
                }
                "requestNativePermissions" -> {
                    val permissionsToRequest = arrayOf(
                        android.Manifest.permission.BLUETOOTH_SCAN,
                        android.Manifest.permission.BLUETOOTH_CONNECT,
                        android.Manifest.permission.BLUETOOTH_ADVERTISE,
                        android.Manifest.permission.ACCESS_FINE_LOCATION
                    )
                    
                    // Verificar si algún permiso fue rechazado permanentemente
                    val shouldShowRationale = permissionsToRequest.any { permission ->
                        ActivityCompat.shouldShowRequestPermissionRationale(this, permission)
                    }
                    
                    Log.i(TAG, "Solicitando permisos: ${permissionsToRequest.joinToString()}")
                    Log.i(TAG, "Debería mostrar explicación: $shouldShowRationale")
                    
                    permissionsResult = result
                    ActivityCompat.requestPermissions(this, permissionsToRequest, REQUEST_PERMISSIONS)
                }
                "openAppSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    val uri = android.net.Uri.fromParts("package", packageName, null)
                    intent.data = uri
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startBleAdvertising(userId: Int) {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()

        val now = java.util.Calendar.getInstance()
        val year = (now.get(java.util.Calendar.YEAR)%100).toByte()
        val month = (now.get(java.util.Calendar.MONTH) + 1).toByte()
        val day = now.get(java.util.Calendar.DAY_OF_MONTH).toByte()
        val hour = now.get(java.util.Calendar.HOUR_OF_DAY).toByte()
        val minute = now.get(java.util.Calendar.MINUTE).toByte()

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) return

        advertiser = bluetoothAdapter.bluetoothLeAdvertiser
        if (advertiser == null) return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .build()
            
        val manufacturerData = byteArrayOf( (userId shr 8).toByte(), (userId and 0xFF).toByte(),  year, month, day, hour, minute)
       
        val data = AdvertiseData.Builder()
            .addManufacturerData(0xFFFF, manufacturerData)
            .setIncludeDeviceName(false)
            .build()

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                Log.i(TAG, "Advertising iniciado con ID: $userId")
            }
            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "Error al iniciar advertising: $errorCode")
            }
        }
        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopBleAdvertising() {
        advertiser?.stopAdvertising(advertiseCallback)
        Log.i(TAG, "Advertising detenido")
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == REQUEST_PERMISSIONS) {
            val results = mutableMapOf<String, Boolean>()
            for (i in permissions.indices) {
                results[permissions[i]] = grantResults[i] == PackageManager.PERMISSION_GRANTED
            }
            
            Log.i(TAG, "Permisos completados: $results")
            permissionsResult?.success(results)
            permissionsResult = null
        }
    }
}
