package com.codexisland.android

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.scrollTo
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.isDisplayed
import androidx.test.espresso.matcher.ViewMatchers.withId
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.codexisland.android.shell.bootstrap.ShellBootstrapViewModel
import com.codexisland.android.shell.runtime.EngineRuntimeGateway
import com.codexisland.android.shell.runtime.EngineRuntimeProbeResult
import com.codexisland.android.shell.storage.ShellProfile
import com.codexisland.android.shell.storage.ShellProfileStore
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityInstrumentedTest {
    @After
    fun tearDown() {
        MainActivityTestOverrides.viewModelFactory = null
    }

    @Test
    fun bootstrapWorkspaceIsVisible() {
        installSmokeTestFactory()

        ActivityScenario.launch(MainActivity::class.java).use {
            onView(withText(R.string.shell_header_title)).check(matches(isDisplayed()))
            onView(withId(R.id.runtimeStatusChip)).check(matches(isDisplayed()))
            onView(withId(R.id.hostConnectionEditText)).perform(scrollTo()).check(matches(isDisplayed()))
        }
    }

    private fun installSmokeTestFactory() {
        MainActivityTestOverrides.viewModelFactory = object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                @Suppress("UNCHECKED_CAST")
                return ShellBootstrapViewModel(
                    profileStore = StaticShellProfileStore(),
                    runtimeGateway = FakeRuntimeGateway()
                ) as T
            }
        }
    }

    private class StaticShellProfileStore(
        private var profile: ShellProfile = ShellProfile(
            deviceName = "Android Companion",
            hosts = emptyList(),
            activeHostId = null
        )
    ) : ShellProfileStore {
        override fun load(): ShellProfile = profile

        override fun save(profile: ShellProfile) {
            this.profile = profile
        }
    }

    private class FakeRuntimeGateway : EngineRuntimeGateway {
        override fun probe(
            hostProfile: com.codexisland.android.shell.storage.HostProfile?,
            deviceName: String,
            pairingCode: String,
            draftMessage: String,
        ): EngineRuntimeProbeResult {
            return EngineRuntimeProbeResult(
                runtimeLinked = false,
                engineStatus = "not linked",
                bindingSurface = "stub",
                connection = "disconnected",
                commandQueue = "0 pending",
                pairedDevices = "0 paired",
                reconnect = "idle",
                diagnostics = "smoke test runtime",
                lastError = "无",
                helloCommandPreview = "{}",
                pairStartCommandPreview = "pair-start",
                pairConfirmCommandPreview = "pair-confirm",
                reconnectCommandPreview = "reconnect",
                threadListCommandPreview = "thread-list",
                threadStartCommandPreview = "thread-start",
                threadResumeCommandPreview = "thread-resume",
                turnStartCommandPreview = "turn-start",
                turnSteerCommandPreview = "turn-steer",
                interruptCommandPreview = "interrupt",
                nextSteps = "none",
                authToken = null,
                pairingCode = pairingCode.ifBlank { null },
                threadListSummary = "还没有活动中的会话。",
                activeThreadSummary = "还没有创建会话。",
                chatTranscript = "还没有对话内容。",
                approvalSummary = "当前没有待处理审批。",
                userInputSummary = "当前没有待补充输入。"
            )
        }

        override fun refresh() = Unit

        override fun startThread() = Unit

        override fun selectNextThread() = Unit

        override fun resumeThread() = Unit

        override fun sendMessage(message: String) = Unit

        override fun interruptThread() = Unit

        override fun respondToApproval(allow: Boolean) = Unit

        override fun submitUserInput(answer: String) = Unit
    }
}
