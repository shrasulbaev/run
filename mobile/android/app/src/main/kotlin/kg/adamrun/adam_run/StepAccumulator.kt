package kg.adamrun.adam_run

/** Monotonic hardware totals. Never count the pre-install baseline or assign
 * an ambiguous overnight/reboot gap to the new day. Health Connect backfills it. */
data class StepAccumulator(var lastRaw: Long = -1, var lastBoot: Long = -1, var day: String = "", var total: Int = 0) {
    fun accept(raw: Long, boot: Long, eventDay: String): Int {
        val sameDay = day == eventDay
        if (!sameDay) total = 0
        val sameBoot = lastBoot >= 0 && kotlin.math.abs(boot - lastBoot) < 5000
        if (sameDay && sameBoot && lastRaw >= 0 && raw >= lastRaw) total += (raw - lastRaw).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        lastRaw = raw
        lastBoot = boot
        day = eventDay
        return total
    }
}
