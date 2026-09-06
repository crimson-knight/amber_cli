package dev.amber.generated

import android.os.Bundle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.assetpipeline.androidhost.CrystalBridge
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Separate read-only process proof; never increments or saves application data. */
@RunWith(AndroidJUnit4::class)
class NativeRestorationTest {
    @Test fun aDifferentProcessRestoresExactUnicodeState() {
        val arguments = InstrumentationRegistry.getArguments()
        val count = requireNotNull(arguments.getString("expected_count")).toInt()
        val previous = requireNotNull(arguments.getString("previous_pid")).toInt()
        assertNotEquals(previous, android.os.Process.myPid())
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        try {
            for (text in listOf("Count: $count", "Name: ${NativeApplicationTest.EXPECTED_NAME}", "Restored from local storage.")) {
                assertTrue("New process did not restore exact native text: $text", device.wait(Until.hasObject(By.text(text)), 5000L))
            }
        } finally { scenario.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
            assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices())
        }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("restored_process", android.os.Process.myPid().toString())
        })
    }
}
