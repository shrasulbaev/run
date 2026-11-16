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
    @Test fun staleResetAndDuplicateTimestampDoNotInflate() {
        val s = StepAccumulator()
        assertEquals(0, s.accept(1000,10000,"2026-11-17",1000000000))
        assertEquals(5, s.accept(1005,10000,"2026-11-17",3000000000))
        assertEquals(5, s.accept(995,10000,"2026-11-17",4000000000))
        assertEquals(5, s.accept(1005,10000,"2026-11-17",5000000000))
        assertEquals(5, s.accept(1010,10000,"2026-11-17",3000000000))
        assertEquals(10, s.accept(1010,10000,"2026-11-17",7000000000))
    }
    @Test fun impossibleBurstIsIgnored() {
        val s = StepAccumulator(1000,10000,"2026-11-17",100,1000000000)
        assertEquals(100,s.accept(9000,10000,"2026-11-17",2000000000))
        assertEquals(103,s.accept(1003,10000,"2026-11-17",3000000000))
    }
}
