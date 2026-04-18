package com.codexisland.android

import android.content.Context
import android.os.SystemClock
import android.widget.TextView
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.action.ViewActions.scrollTo
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.withId
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.codexisland.android.shell.bootstrap.ShellBootstrapViewModel
import com.codexisland.android.shell.runtime.UniffiEngineRuntimeGateway
import com.codexisland.android.shell.storage.HostProfile
import com.codexisland.android.shell.storage.ShellProfile
import com.codexisland.android.shell.storage.ShellProfileStore
import org.hamcrest.CoreMatchers.containsString
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class MainActivityLiveSshInstrumentedTest {
    @After
    fun tearDown() {
        MainActivityTestOverrides.viewModelFactory = null
    }

    @Test
    fun liveSshDirectConnectsAndLoadsRemoteThreads() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("live ssh args not provided", args.containsKey("ssh_target"))
        val sshTarget = requireArg(args, "ssh_target")
        val sshPublicKey = args.getString("ssh_public_key").orEmpty()
        val sshPublicKeyPkcs8 = requireArg(args, "ssh_public_key_pkcs8")
        val sshPrivateKeyPkcs8 = requireArg(args, "ssh_private_key_pkcs8")
        val context = ApplicationProvider.getApplicationContext<Context>()
        installLiveFactory(
            context = context,
            sshTarget = sshTarget,
            sshPublicKey = sshPublicKey,
            sshPublicKeyPkcs8 = sshPublicKeyPkcs8,
            sshPrivateKeyPkcs8 = sshPrivateKeyPkcs8
        )

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            onView(withId(R.id.toggleConnectionButton)).perform(scrollTo(), click())
            onView(withId(R.id.refreshButton)).perform(scrollTo(), click())
            onView(withId(R.id.toggleDebugButton)).perform(scrollTo(), click())

            waitForCondition(scenario, timeoutMs = 20_000L) { activity ->
                val connection = activity.findViewById<TextView>(R.id.connectionValue).text.toString()
                val threadList = activity.findViewById<TextView>(R.id.threadListValue).text.toString()
                connection.contains("connected") && !threadList.contains("还没有活动中的会话")
            }

            onView(withId(R.id.connectionValue))
                .perform(scrollTo())
                .check(matches(withText(containsString("connected"))))

            scenario.onActivity { activity ->
                val threadList = activity.findViewById<TextView>(R.id.threadListValue).text.toString()
                val diagnostics = activity.findViewById<TextView>(R.id.diagnosticsValue).text.toString()
                assertTrue("expected remote thread list, got: $threadList", threadList.contains("•"))
                assertTrue("expected diagnostics to mention thread count, got: $diagnostics", diagnostics.contains("会话数="))
            }
        }
    }

    private fun installLiveFactory(
        context: Context,
        sshTarget: String,
        sshPublicKey: String,
        sshPublicKeyPkcs8: String,
        sshPrivateKeyPkcs8: String,
    ) {
        val hostId = UUID.randomUUID().toString()
        val store = StaticShellProfileStore(
            ShellProfile(
                deviceName = "Android Companion",
                hosts = listOf(
                    HostProfile(
                        id = hostId,
                        displayName = "Linux 验收机",
                        hostAddress = sshTarget,
                        authToken = null,
                        sshPassword = null,
                        lastPairingCode = null,
                        sshPublicKey = sshPublicKey,
                        sshPublicKeyPkcs8 = sshPublicKeyPkcs8,
                        sshPrivateKeyPkcs8 = sshPrivateKeyPkcs8
                    )
                ),
                activeHostId = hostId
            )
        )
        MainActivityTestOverrides.viewModelFactory = object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                val gateway = UniffiEngineRuntimeGateway(
                    clientName = "Codex Island Android",
                    clientVersion = "0.1.0",
                    nativeLibraryDir = context.applicationInfo.nativeLibraryDir
                )
                @Suppress("UNCHECKED_CAST")
                return ShellBootstrapViewModel(store, gateway, null) as T
            }
        }
    }

    private fun waitForCondition(
        scenario: ActivityScenario<MainActivity>,
        timeoutMs: Long,
        condition: (MainActivity) -> Boolean,
    ) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            var matched = false
            scenario.onActivity { activity ->
                matched = condition(activity)
            }
            if (matched) {
                return
            }
            SystemClock.sleep(500)
        }
        scenario.onActivity { activity ->
            val connection = activity.findViewById<TextView>(R.id.connectionValue).text.toString()
            val threadList = activity.findViewById<TextView>(R.id.threadListValue).text.toString()
            val diagnostics = activity.findViewById<TextView>(R.id.diagnosticsValue).text.toString()
            val lastError = activity.findViewById<TextView>(R.id.lastErrorValue).text.toString()
            throw AssertionError(
                "Timed out waiting for live SSH connection. " +
                    "connection=$connection threadList=$threadList diagnostics=$diagnostics lastError=$lastError"
            )
        }
    }

    private fun requireArg(args: android.os.Bundle, key: String): String =
        args.getString(key)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Missing instrumentation argument: $key")

    private class StaticShellProfileStore(
        private var profile: ShellProfile
    ) : ShellProfileStore {
        override fun load(): ShellProfile = profile

        override fun save(profile: ShellProfile) {
            this.profile = profile
        }
    }
}
