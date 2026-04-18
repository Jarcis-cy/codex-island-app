package com.codexisland.android

import android.view.View
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso.closeSoftKeyboard
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.action.ViewActions.replaceText
import androidx.test.espresso.action.ViewActions.scrollTo
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.Visibility
import androidx.test.espresso.matcher.ViewMatchers.isDisplayed
import androidx.test.espresso.matcher.ViewMatchers.withEffectiveVisibility
import androidx.test.espresso.matcher.ViewMatchers.withId
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.codexisland.android.shell.bootstrap.ShellBootstrapViewModel
import com.codexisland.android.shell.runtime.EngineRuntimeGateway
import com.codexisland.android.shell.runtime.EngineRuntimeProbeResult
import com.codexisland.android.shell.storage.GeneratedSshKeyPair
import com.codexisland.android.shell.storage.HostProfile
import com.codexisland.android.shell.storage.HostProfileEditor
import com.codexisland.android.shell.storage.SecureShellStore
import com.codexisland.android.shell.storage.ShellProfile
import com.codexisland.android.shell.storage.ShellProfileStore
import org.hamcrest.CoreMatchers.containsString
import org.hamcrest.CoreMatchers.startsWith
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityWorkflowInstrumentedTest {
    @After
    fun tearDown() {
        MainActivityTestOverrides.viewModelFactory = null
    }

    @Test
    fun sshModeShowsKeyToolsAndGeneratesInstallCommand() {
        installTestFactory()

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            onView(withId(R.id.hostConnectionEditText)).perform(
                scrollTo(),
                replaceText("ssh://deploy@linux.example.internal")
            )
            closeSoftKeyboard()
            onView(withId(R.id.hostDisplayNameEditText)).perform(
                scrollTo(),
                replaceText("Linux 验收机")
            )
            closeSoftKeyboard()

            closeSoftKeyboard()
            scenario.onActivity { activity ->
                activity.findViewById<View>(R.id.saveHostButton).performClick()
            }
            onView(withId(R.id.toggleConnectionButton)).perform(scrollTo(), click())

            onView(withId(R.id.authTokenInputLayout))
                .check(matches(withEffectiveVisibility(Visibility.GONE)))
            onView(withId(R.id.sshPasswordInputLayout))
                .perform(scrollTo())
                .check(matches(isDisplayed()))
            onView(withId(R.id.generateSshKeyButton))
                .perform(scrollTo())
                .check(matches(isDisplayed()))
                .perform(scrollTo(), click())

            onView(withId(R.id.sshPublicKeyValue))
                .perform(scrollTo())
                .check(matches(withText(startsWith("ssh-rsa "))))
            onView(withId(R.id.sshInstallCommandValue))
                .perform(scrollTo())
                .check(matches(withText(containsString("authorized_keys"))))
            onView(withId(R.id.runtimeStatusChip))
                .check(matches(withText("SSH 直连")))
        }
    }

    @Test
    fun threadWorkflowHandlesApprovalUserInputAndInterrupt() {
        installTestFactory()

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            onView(withId(R.id.hostConnectionEditText)).perform(
                scrollTo(),
                replaceText("macbook.example.internal:7331")
            )
            closeSoftKeyboard()
            closeSoftKeyboard()
            scenario.onActivity { activity ->
                activity.findViewById<View>(R.id.saveHostButton).performClick()
            }

            onView(withId(R.id.startThreadButton)).perform(scrollTo(), click())
            onView(withId(R.id.messageEditText)).perform(
                scrollTo(),
                replaceText("please /approve apply_patch")
            )
            closeSoftKeyboard()
            onView(withId(R.id.sendMessageButton)).perform(scrollTo(), click())
            onView(withId(R.id.approvalValue))
                .check(matches(withText(containsString("命令审批"))))

            onView(withId(R.id.allowApprovalButton)).perform(scrollTo(), click())
            onView(withId(R.id.approvalValue))
                .check(matches(withText(containsString("当前没有待处理审批"))))

            onView(withId(R.id.messageEditText)).perform(
                scrollTo(),
                replaceText("please /input env")
            )
            closeSoftKeyboard()
            onView(withId(R.id.sendMessageButton)).perform(scrollTo(), click())
            onView(withId(R.id.userInputValue))
                .check(matches(withText(containsString("请输入部署环境"))))

            onView(withId(R.id.userInputAnswerEditText)).perform(
                scrollTo(),
                replaceText("production")
            )
            closeSoftKeyboard()
            onView(withId(R.id.submitInputButton)).perform(scrollTo(), click())
            SystemClock.sleep(1_200)
            onView(withId(R.id.userInputCard))
                .check(matches(withEffectiveVisibility(Visibility.GONE)))
            onView(withId(R.id.chatTranscriptValue))
                .check(matches(withText(containsString("production"))))

            onView(withId(R.id.interruptThreadButton)).perform(scrollTo(), click())
            onView(withId(R.id.activeThreadValue))
                .check(matches(withText(containsString("interrupted"))))
        }
    }

    private fun installTestFactory() {
        val store = FakeShellProfileStore()
        val runtime = FakeRuntimeGateway()
        val editor = FakeHostProfileEditor()
        MainActivityTestOverrides.viewModelFactory = object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                @Suppress("UNCHECKED_CAST")
                return ShellBootstrapViewModel(store, runtime, editor) as T
            }
        }
    }

    private class FakeShellProfileStore(
        var profile: ShellProfile = ShellProfile(
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
        private var startedThread = false
        private var activeHost: HostProfile? = null
        private var threadStatus = "idle"
        private var approvalSummary = "当前没有待处理审批。"
        private var userInputSummary = "当前没有待补充输入。"
        private val transcript = mutableListOf<String>()

        override fun probe(
            hostProfile: HostProfile?,
            deviceName: String,
            pairingCode: String,
            draftMessage: String,
        ): EngineRuntimeProbeResult {
            activeHost = hostProfile
            val authToken = hostProfile?.authToken
            return EngineRuntimeProbeResult(
                runtimeLinked = true,
                engineStatus = "ok",
                bindingSurface = "surface 1",
                connection = "connected",
                commandQueue = "0 pending",
                pairedDevices = "1 paired",
                reconnect = "idle",
                diagnostics = "connect=1",
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
                nextSteps = "next",
                authToken = authToken,
                pairingCode = pairingCode.ifBlank { hostProfile?.lastPairingCode },
                threadListSummary = if (startedThread) {
                    "• 当前 Thread 1 [$threadStatus]"
                } else {
                    "还没有活动中的会话。"
                },
                activeThreadSummary = if (startedThread) {
                    "Thread 1\nthread-1\nstatus=$threadStatus · turn=turn-1"
                } else {
                    "还没有创建会话。"
                },
                chatTranscript = transcript.joinToString("\n\n").ifBlank { "还没有对话内容。" },
                approvalSummary = approvalSummary,
                userInputSummary = userInputSummary
            )
        }

        override fun refresh() = Unit

        override fun startThread() {
            startedThread = true
            threadStatus = "active"
        }

        override fun selectNextThread() = Unit

        override fun resumeThread() {
            threadStatus = "resumed"
        }

        override fun sendMessage(message: String) {
            transcript += "[user] $message"
            when {
                message.contains("/approve") -> {
                    approvalSummary = "命令审批\napply_patch"
                    userInputSummary = "当前没有待补充输入。"
                    threadStatus = "waiting_approval"
                }

                message.contains("/input") -> {
                    approvalSummary = "当前没有待处理审批。"
                    userInputSummary = "请输入部署环境"
                    threadStatus = "waiting_input"
                }

                else -> {
                    approvalSummary = "当前没有待处理审批。"
                    userInputSummary = "当前没有待补充输入。"
                    threadStatus = "active"
                }
            }
        }

        override fun interruptThread() {
            threadStatus = "interrupted"
            transcript += "[system] Turn interrupted."
        }

        override fun respondToApproval(allow: Boolean) {
            approvalSummary = "当前没有待处理审批。"
            threadStatus = if (allow) "active" else "idle"
            transcript += if (allow) "[approval] accepted" else "[approval] declined"
        }

        override fun submitUserInput(answer: String) {
            userInputSummary = "当前没有待补充输入。"
            threadStatus = "active"
            transcript += "[user-input] $answer"
        }
    }

    private class FakeHostProfileEditor : HostProfileEditor {
        override fun upsertHost(
            current: ShellProfile,
            rawConnectionInput: String,
            explicitDisplayName: String,
            explicitAuthToken: String,
            explicitSshPassword: String,
            pairingCode: String,
        ): ShellProfile {
            val parsed = SecureShellStore.parseHostInput(rawConnectionInput)
            val host = HostProfile(
                id = "host-${parsed.hostAddress}",
                displayName = explicitDisplayName.ifBlank { parsed.displayName ?: "Host" },
                hostAddress = parsed.hostAddress,
                authToken = explicitAuthToken.trim().ifBlank { parsed.authToken.orEmpty() }.ifBlank { null },
                sshPassword = explicitSshPassword.trim().ifBlank { parsed.sshPassword.orEmpty() }.ifBlank { null },
                lastPairingCode = pairingCode.trim().ifBlank { parsed.pairingCode.orEmpty() }.ifBlank { null },
                sshPublicKey = null,
                sshPublicKeyPkcs8 = null,
                sshPrivateKeyPkcs8 = null
            )
            return current.copy(
                hosts = listOf(host),
                activeHostId = host.id
            )
        }

        override fun selectHost(current: ShellProfile, hostId: String): ShellProfile {
            return current.copy(activeHostId = hostId)
        }

        override fun activeHost(profile: ShellProfile): HostProfile? {
            return profile.hosts.firstOrNull { it.id == profile.activeHostId } ?: profile.hosts.firstOrNull()
        }

        override fun attachSshKeyPair(
            current: ShellProfile,
            hostId: String,
            keyPair: GeneratedSshKeyPair,
        ): ShellProfile {
            return current.copy(
                hosts = current.hosts.map { host ->
                    if (host.id == hostId) {
                        host.copy(
                            sshPublicKey = keyPair.publicKeyOpenSsh,
                            sshPublicKeyPkcs8 = keyPair.publicKeyPkcs8Base64,
                            sshPrivateKeyPkcs8 = keyPair.privateKeyPkcs8Base64
                        )
                    } else {
                        host
                    }
                }
            )
        }
    }
}
