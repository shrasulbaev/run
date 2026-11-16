package kg.adamrun.adam_run

import android.app.*
import android.content.Context
import android.content.Intent
import android.hardware.*
import android.os.IBinder
import android.os.SystemClock
import java.time.Instant
import java.time.ZoneId

class StepSensorService : Service(), SensorEventListener {
    private lateinit var manager: SensorManager
    private lateinit var accumulator: StepAccumulator
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel("steps", "Шагомер", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        startForeground(41, Notification.Builder(this, "steps").setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle("ADAM RUN · шагомер включён").setContentText("Шаги считает датчик телефона").setContentIntent(open).setOngoing(true).build())
        val p = getSharedPreferences("adam_steps", MODE_PRIVATE)
        val day = p.getString("lastDay", "")!!
        accumulator = StepAccumulator(p.getLong("lastRaw", -1), p.getLong("lastBoot", -1), day, p.getInt("day.$day", 0), p.getLong("lastTimestamp", 0))
        manager = getSystemService(SENSOR_SERVICE) as SensorManager
        manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)?.let { manager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY
    override fun onSensorChanged(event: SensorEvent) {
        val boot = System.currentTimeMillis() - SystemClock.elapsedRealtime()
        val eventTime = boot + event.timestamp / 1_000_000
        val day = Instant.ofEpochMilli(eventTime).atZone(ZoneId.systemDefault()).toLocalDate().toString()
        val bootId = android.provider.Settings.Global.getInt(contentResolver, android.provider.Settings.Global.BOOT_COUNT, -1)
        val stableBoot = if (bootId >= 0) bootId.toLong() * 10000 else boot
        val total = accumulator.accept(event.values[0].toLong(), stableBoot, day, event.timestamp)
        getSharedPreferences("adam_steps", MODE_PRIVATE).edit().putLong("lastRaw", accumulator.lastRaw).putLong("lastBoot", accumulator.lastBoot).putLong("lastTimestamp", accumulator.lastTimestamp).putString("lastDay", accumulator.day).putInt("day.${accumulator.day}", total).apply()
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onDestroy() { manager.unregisterListener(this); super.onDestroy() }
    companion object {
        fun hasSensor(context: Context) = (context.getSystemService(SENSOR_SERVICE) as SensorManager).getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
    }
}
