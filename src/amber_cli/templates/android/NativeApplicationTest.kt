package dev.amber.generated

import android.content.Context
import android.os.Build
import android.widget.EditText
import android.widget.ImageView
import android.view.View
import android.view.KeyEvent
import kotlin.math.roundToInt
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.InputMethodManager
import android.os.Bundle
import java.util.regex.Pattern
import androidx.test.core.app.ActivityScenario
import androidx.lifecycle.Lifecycle
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.*
import androidx.test.espresso.matcher.ViewMatchers.*
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.assetpipeline.androidhost.CrystalBridge
import dev.assetpipeline.androidhost.CrystalLinearLayout
import dev.assetpipeline.androidhost.HostSession
import dev.assetpipeline.androidhost.NativeViewState
import dev.assetpipeline.androidhost.NativeTestIds
import dev.assetpipeline.androidhost.NativeSemantics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeApplicationTest {
    companion object {
        const val EXPECTED_NAME = "Android 雪 😀 e\u0301"
        // The first launch after an install pays for the Crystal runtime and the stored
        // snapshot on a cold emulator; later waits keep the shorter budget.
        const val FIRST_RENDER_TIMEOUT_MS = 10000L
    }
    private fun awaitText(text: String) {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        assertTrue("Native view did not display: $text", device.wait(Until.hasObject(By.text(text)), 5000L))
    }
    private fun editor(activity: MainActivity) = requireNotNull(NativeViewState.nodes(activity.window.decorView).single { it.identity.key == "counter-name" }.editor)
    private fun assertEditorState(activity: MainActivity) {
        val field = editor(activity)
        assertTrue(field.hasFocus())
        assertEquals("x", field.text.toString())
        assertEquals(0, field.selectionStart); assertEquals(1, field.selectionEnd)
    }
    private fun publishExternalEdit(editor: EditText) {
        // Our direct test connection is separate from the attached keyboard's
        // session. Publish its new surrounding text before queued IME edits run.
        val keyboard = editor.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (Build.VERSION.SDK_INT >= 33) keyboard.invalidateInput(editor)
        else keyboard.restartInput(editor)
    }
    @Test
    fun sharedStateHandlesActionsValidationAndRecreation() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        var expectedCount = 0
        try {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            val countView = requireNotNull(device.wait(Until.findObject(By.text(Pattern.compile("^Count: [0-9]+$"))), FIRST_RENDER_TIMEOUT_MS))
            expectedCount = countView.text.removePrefix("Count: ").toInt() + 1
            awaitText("Session: Foreground / starts 1 / backgrounds 0")
            onView(NativeTestIds.withTestId("counter-app-mark")).check { view, error ->
                if (error != null) throw error
                val image = view as ImageView
                assertTrue("The generated application's bundled image must load", image.drawable != null)
                assertEquals(ImageView.ScaleType.FIT_CENTER, image.scaleType)
                assertTrue(image.contentDescription.toString().endsWith(" app mark"))
            }
            onView(NativeTestIds.withTestId("counter-name")).check { view, error ->
                if (error != null) throw error
                val maximum = (280.5f * view.resources.displayMetrics.density).roundToInt()
                assertTrue("The generated field must obey its shared maximum width", view.width in 1..maximum)
                assertTrue("The native bounds wrapper must retain the field", (view.parent as View).width >= view.width)
                val info = NativeSemantics.target(view).createAccessibilityNodeInfo()
                assertNull(info.contentDescription)
                assertTrue(info.isEditable)
                assertEquals("Name", info.hintText.toString())
                assertEquals("counter-name", info.extras.getString("dev.assetpipeline.test_id"))
                assertEquals("counter-name-field", info.extras.getString("dev.assetpipeline.accessibility_identifier"))
            }
            onView(NativeTestIds.withTestId("counter-actions")).check { view, error ->
                if (error != null) throw error
                val row = view as CrystalLinearLayout
                assertTrue("The generated app must exercise shared equal-width distribution", row.crystalFillEqually)
                assertEquals(2, row.childCount)
                val first = row.getChildAt(0)
                val second = row.getChildAt(1)
                assertTrue(first.width > 0 && second.width > 0)
                assertTrue(kotlin.math.abs(first.width - second.width) <= 1)
                val gap = (12f * row.resources.displayMetrics.density).roundToInt()
                assertEquals(row.width - row.paddingLeft - row.paddingRight, first.width + second.width + gap)
            }
            onView(NativeTestIds.withTestId("1.1-welcome-label")).check { view, error ->
                if (error != null) throw error
                assertTrue(view.createAccessibilityNodeInfo().isHeading)
            }
            scenario.onActivity { activity ->
                CrystalBridge.foregroundHost(activity)
                CrystalBridge.foregroundHost(activity)
                assertThrows(IllegalStateException::class.java) { CrystalBridge.attachHost(Any()) }
                assertThrows(IllegalStateException::class.java) { CrystalBridge.closeSession() }
            }
            // Instrumentation's thread must not enter Crystal UI/application code.
            assertThrows(IllegalStateException::class.java) { CrystalBridge.dispatchVoidCallback(0) }
            onView(withText("Increment")).perform(scrollTo(), click())
            awaitText("Count: $expectedCount")
            awaitText("Saved locally.")
            scenario.onActivity { activity ->
                expectedCount++
                assertTrue(activity.dispatchKeyShortcutEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_I, 0, KeyEvent.META_CTRL_ON)))
                assertTrue(activity.dispatchKeyShortcutEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_I, 1, KeyEvent.META_CTRL_ON)))
                assertTrue(activity.dispatchKeyShortcutEvent(KeyEvent(0, 0, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_I, 0, KeyEvent.META_CTRL_ON)))
            }
            awaitText("Count: $expectedCount")
            awaitText("Saved locally.")
            onView(isAssignableFrom(EditText::class.java)).perform(scrollTo(), replaceText(""), typeText("Android"))
            onView(isAssignableFrom(EditText::class.java)).check { view, error ->
                if (error != null) throw error
                val editor = view as EditText
                assertEquals("Android", editor.text.toString())
                val connection = requireNotNull(editor.onCreateInputConnection(EditorInfo()))
                // Selection does not override a composing range: commitText
                // replaces composition first. Model that real keyboard state
                // deterministically, then finish it before appending Unicode.
                assertTrue(connection.setComposingRegion(0, editor.text.length))
                assertEquals(0, BaseInputConnection.getComposingSpanStart(editor.text))
                assertEquals(editor.text.length, BaseInputConnection.getComposingSpanEnd(editor.text))
                assertTrue(connection.finishComposingText())
                assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.text))
                assertEquals("Android", editor.text.toString())
                assertTrue(connection.setSelection(editor.text.length, editor.text.length))
                assertTrue(connection.commitText(" 雪 😀 e\u0301", 1))
                assertEquals(EXPECTED_NAME, editor.text.toString())
                publishExternalEdit(editor)
            }
            onView(isAssignableFrom(EditText::class.java)).perform(closeSoftKeyboard())
            onView(withText("Save name")).perform(scrollTo(), click())
            awaitText("Name: $EXPECTED_NAME")
            awaitText("Saved locally.")
            onView(isAssignableFrom(EditText::class.java)).perform(scrollTo(), replaceText("x"), closeSoftKeyboard())
            onView(withText("Save name")).perform(scrollTo(), click())
            awaitText("Use at least two characters.")
            scenario.onActivity { activity ->
                val field = editor(activity)
                assertTrue(field.requestFocus())
                field.setSelection(0, 1)
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                assertEquals(HostSession.State.BACKGROUND, CrystalBridge.debugSessionState())
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            onView(withText("Session: Foreground / starts 1 / backgrounds 1")).perform(scrollTo())
            awaitText("Session: Foreground / starts 1 / backgrounds 1")
            scenario.recreate()
            awaitText("Session: Foreground / starts 1 / backgrounds 2")
            awaitText("Name: $EXPECTED_NAME")
            awaitText("Count: $expectedCount")
            scenario.onActivity { assertEditorState(it) }
            scenario.onActivity { assertTrue(!CrystalBridge.canNavigateBack()) }
            onView(withText("Open details")).perform(scrollTo(), click())
            awaitText("Native details")
            awaitText("Count: $expectedCount")
            awaitText("Name: $EXPECTED_NAME")
            scenario.onActivity { assertTrue(CrystalBridge.canNavigateBack()) }
            onView(withContentDescription("Navigate up")).perform(scrollTo()).check { view, error ->
                if (error != null) throw error
                // Native accessibility activation avoids a scheduled emulator
                // stretching this tooltip-enabled control's tap into a long press.
                assertTrue(view.performAccessibilityAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK, null))
            }
            awaitText("Use at least two characters.")
            scenario.onActivity { assertEditorState(it) }
            onView(withText("Open details")).perform(scrollTo(), click())
            awaitText("Native details")
            device.pressBack()
            awaitText("Use at least two characters.")
            scenario.onActivity { assertEditorState(it) }
            scenario.onActivity { assertTrue(!CrystalBridge.canNavigateBack()) }
        } finally { scenario.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
            assertEquals(HostSession.State.BACKGROUND, CrystalBridge.debugSessionState())
            assertEquals(Pair(0, 0), CrystalBridge.debugPendingServices())
        }
        // A new Activity in the same process is still the same Amber session.
        val reopened = ActivityScenario.launch(MainActivity::class.java)
        try {
            awaitText("Session: Foreground / starts 1 / backgrounds 3")
            awaitText("Count: $expectedCount")
            awaitText("Name: $EXPECTED_NAME")
        } finally { reopened.close() }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            assertEquals(CrystalBridge.NativeDebugCounts(0, 0), CrystalBridge.debugCounts())
            CrystalBridge.closeSession()
            CrystalBridge.closeSession()
            assertEquals(HostSession.State.STOPPED, CrystalBridge.debugSessionState())
            assertThrows(IllegalStateException::class.java) { CrystalBridge.attachHost(Any()) }
        }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("persisted_count", expectedCount.toString())
            putString("persisted_process", android.os.Process.myPid().toString())
        })
    }
}
