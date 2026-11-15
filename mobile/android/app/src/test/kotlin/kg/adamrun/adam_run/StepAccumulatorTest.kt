package kg.adamrun.adam_run
import org.junit.Assert.assertEquals
import org.junit.Test

class StepAccumulatorTest {
    @Test fun baselineAndRepeatedReadAreNotSteps() {
        val s=StepAccumulator()
        assertEquals(0,s.accept(10000,1000,"2026-11-16"))
        assertEquals(20,s.accept(10020,1000,"2026-11-16"))
        assertEquals(20,s.accept(10020,1000,"2026-11-16"))
    }
    @Test fun rebootAndCounterResetCannotAddLifetimeTotal() {
        val s=StepAccumulator(1000,1000,"2026-11-16",250)
        assertEquals(250,s.accept(12,999999,"2026-11-16"))
        assertEquals(255,s.accept(17,999999,"2026-11-16"))
    }
    @Test fun midnightDoesNotAssignYesterdayToToday() {
        val s=StepAccumulator(1000,1000,"2026-11-15",8000)
        assertEquals(0,s.accept(1300,1000,"2026-11-16"))
        assertEquals(5,s.accept(1305,1000,"2026-11-16"))
    }
}
