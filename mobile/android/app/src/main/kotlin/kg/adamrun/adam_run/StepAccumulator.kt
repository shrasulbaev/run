package kg.adamrun.adam_run

/** One hardware source. Repeated, out-of-order, reset and implausible readings
 * cannot add lifetime totals or duplicate a previously counted interval. */
data class StepAccumulator(var lastRaw: Long = -1, var lastBoot: Long = -1, var day: String = "", var total: Int = 0, var lastTimestamp: Long = 0) {
    fun accept(raw: Long, boot: Long, eventDay: String, timestamp: Long = 0): Int {
        if (raw < 0) return total
        val sameBoot = lastBoot >= 0 && kotlin.math.abs(boot - lastBoot) < 5000
        if (sameBoot && timestamp > 0 && lastTimestamp > 0 && timestamp <= lastTimestamp) return total
        // A lower stale reading followed by the original total must not recount.
        if (sameBoot && lastRaw >= 0 && raw < lastRaw) return total
        val delta = raw - lastRaw
        if (sameBoot && timestamp > 0 && lastTimestamp > 0 && delta > ((timestamp-lastTimestamp)/1_000_000_000.0 * 5 + 4)) return total
        val sameDay = day == eventDay
        if (!sameDay) total = 0
        if (sameDay && sameBoot && lastRaw >= 0) total = (total.toLong() + delta).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        lastRaw = raw
        lastBoot = boot
        lastTimestamp = timestamp
        day = eventDay
        return total
    }
}
