package kg.adamrun.adam_run

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterFragmentActivity() {
    private var pending: MethodChannel.Result? = null
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
            if (call.argument<Boolean>("request") == true) {
                if (!granted()) {
                    getSharedPreferences("adam_steps", MODE_PRIVATE).edit().putBoolean("askedMotion", true).apply()
                    motionPermission.launch(Manifest.permission.ACTIVITY_RECOGNITION)
                } else { startSensor(); finishSnapshot() }
            } else finishSnapshot()
        }
    }
    private fun granted() = Build.VERSION.SDK_INT < 29 || ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
    private fun startSensor() {
        if (StepSensorService.hasSensor(this)) {
            getSharedPreferences("adam_steps", MODE_PRIVATE).edit().putBoolean("enabled", true).apply()
            ContextCompat.startForegroundService(this, Intent(this, StepSensorService::class.java))
        }
    }
    private fun finishSnapshot() {
        val result = pending ?: return
        try {
            val day = LocalDate.now()
            val prefs = getSharedPreferences("adam_steps", MODE_PRIVATE)
            val sensor = StepSensorService.hasSensor(this)
            if (granted() && prefs.getBoolean("enabled", false) && sensor) {
                startSensor()
                val history = (0..6).associate { day.minusDays(it.toLong()).toString().let { key -> key to prefs.getInt("day.$key", 0) } }
                result.success(mapOf("status" to "ready", "source" to "Датчик телефона · без часов и других приложений", "count" to history[day.toString()], "day" to day.toString(), "partial" to true, "history" to history))
            } else {
                val denied = !granted() && prefs.getBoolean("askedMotion",false) && Build.VERSION.SDK_INT >= 29 && !shouldShowRequestPermissionRationale(Manifest.permission.ACTIVITY_RECOGNITION)
                result.success(mapOf("status" to if (!sensor) "unsupported" else if (denied) "denied" else "permissionRequired", "source" to "Android"))
            }
        } catch (_: Exception) { result.success(mapOf("status" to "error", "source" to "Android")) }
        pending = null
    }
}
