package kg.adamrun.adam_run

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.ext.SdkExtensions
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.time.LocalDate
import java.time.ZoneId

class MainActivity : FlutterFragmentActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pending: MethodChannel.Result? = null
    private var historyDay = ""
    private val historyCache = mutableMapOf<String, Int>()
    private val stepPermission = HealthPermission.getReadPermission(StepsRecord::class)
    private val healthPermission = registerForActivityResult(PermissionController.createRequestPermissionResultContract()) { _ -> requestSensor() }
    private val motionPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startSensor()
        finishSnapshot()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kg.adamrun/steps").setMethodCallHandler { call, result ->
            if (call.method != "snapshot") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("busy", "Request in progress", null); return@setMethodCallHandler }
            pending = result
            scope.launch {
                try {
                    if (call.argument<Boolean>("request") == true) {
                        val client = healthClient()
                        if (client != null && !client.permissionController.getGrantedPermissions().contains(stepPermission)) {
                            healthPermission.launch(setOf(stepPermission))
                        } else requestSensor()
                    } else finishSnapshot()
                } catch (_: Exception) { finishSnapshot() }
            }
        }
    }
    private fun healthClient(): HealthConnectClient? =
        if (HealthConnectClient.getSdkStatus(this) == HealthConnectClient.SDK_AVAILABLE) HealthConnectClient.getOrCreate(this) else null

    private fun requestSensor() {
        if (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
            getSharedPreferences("adam_steps", MODE_PRIVATE).edit().putBoolean("askedMotion", true).apply()
            motionPermission.launch(Manifest.permission.ACTIVITY_RECOGNITION)
        } else { startSensor(); finishSnapshot() }
    }
    private fun startSensor() {
        if (StepSensorService.hasSensor(this)) {
            getSharedPreferences("adam_steps", MODE_PRIVATE).edit().putBoolean("enabled", true).apply()
            ContextCompat.startForegroundService(this, Intent(this, StepSensorService::class.java))
        }
    }
    private fun finishSnapshot() {
        scope.launch {
            val result = pending ?: return@launch
            try {
                val day = LocalDate.now()
                val zone = ZoneId.systemDefault()
                val client = healthClient()
                if (client != null && client.permissionController.getGrantedPermissions().contains(stepPermission)) {
                    val history = if (historyDay == day.toString()) historyCache.toMutableMap() else mutableMapOf<String, Int>()
                    val offsets = if (historyDay == day.toString()) 0..0 else 0..6
                    for (offset in offsets) {
                        val date = day.minusDays(offset.toLong())
                        val aggregate = client.aggregate(AggregateRequest(metrics = setOf(StepsRecord.COUNT_TOTAL), timeRangeFilter = TimeRangeFilter.between(date.atStartOfDay(zone).toInstant(), if (offset == 0) java.time.Instant.now() else date.plusDays(1).atStartOfDay(zone).toInstant())))
                        aggregate[StepsRecord.COUNT_TOTAL]?.let { history[date.toString()] = it.toInt() }
                    }
                    historyCache.clear(); historyCache.putAll(history); historyDay = day.toString()
                    val nativeRecording = Build.VERSION.SDK_INT >= 34 && SdkExtensions.getExtensionVersion(34) >= 20
                    if (nativeRecording || history.containsKey(day.toString())) {
                        result.success(mapOf("status" to "ready", "source" to "Health Connect", "count" to (history[day.toString()] ?: 0), "day" to day.toString(), "history" to history, "partial" to false))
                        pending = null
                        return@launch
                    }
                }
                val granted = Build.VERSION.SDK_INT < 29 || ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
                val prefs = getSharedPreferences("adam_steps", MODE_PRIVATE)
                if (granted && prefs.getBoolean("enabled", false) && StepSensorService.hasSensor(this@MainActivity)) {
                    startSensor()
                    val history = (0..6).associate { day.minusDays(it.toLong()).toString().let { key -> key to prefs.getInt("day.$key", 0) } }
                    result.success(mapOf("status" to "ready", "source" to "Датчик телефона", "count" to history[day.toString()], "day" to day.toString(), "partial" to true, "history" to history))
                } else {
                    result.success(mapOf("status" to if (!granted && prefs.getBoolean("askedMotion", false) && Build.VERSION.SDK_INT >= 29 && !shouldShowRequestPermissionRationale(Manifest.permission.ACTIVITY_RECOGNITION)) "denied" else if (client != null || StepSensorService.hasSensor(this@MainActivity)) "permissionRequired" else "unsupported", "source" to "Android"))
                }
            } catch (_: Exception) { result.success(mapOf("status" to "error", "source" to "Android")) }
            pending = null
        }
    }
    override fun onDestroy() { scope.cancel(); pending = null; super.onDestroy() }
}
