package com.codexisland.android.shell.bootstrap

import androidx.arch.core.executor.testing.InstantTaskExecutorRule
import com.codexisland.android.shell.runtime.EngineRuntimeGateway
import com.codexisland.android.shell.runtime.EngineRuntimeProbeResult
import com.codexisland.android.shell.storage.ShellProfile
import com.codexisland.android.shell.storage.ShellProfileStore
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ShellBootstrapViewModelTest {
    @get:Rule
    val instantTaskExecutorRule = InstantTaskExecutorRule()

    @Test
    fun saveShellProfilePersistsNormalizedValues() {
        val store = FakeShellProfileStore()
        val runtime = FakeRuntimeGateway()
        val viewModel = ShellBootstrapViewModel(store, runtime)

        viewModel.saveShellProfile("  Pixel 9  ", "  token-123  ")

        assertEquals("Pixel 9", store.profile.deviceName)
        assertEquals("token-123", store.profile.authToken)
        assertEquals("Pixel 9", viewModel.uiState.value?.deviceName)
        assertEquals("token-123", runtime.lastAuthToken)
    }

    private class FakeShellProfileStore : ShellProfileStore {
        var profile = ShellProfile(
            deviceName = "Android Companion",
            authToken = null
        )

        override fun load(): ShellProfile = profile

        override fun save(profile: ShellProfile) {
            this.profile = profile
        }
    }

    private class FakeRuntimeGateway : EngineRuntimeGateway {
        var lastAuthToken: String? = null

        override fun probe(authToken: String?): EngineRuntimeProbeResult {
            lastAuthToken = authToken
            return EngineRuntimeProbeResult(
                runtimeLinked = true,
                engineStatus = "ok",
                bindingSurface = "surface 1",
                connection = "connecting",
                commandQueue = "2 pending",
                pairedDevices = "0 paired",
                reconnect = "idle",
                diagnostics = "connect=1",
                lastError = "none",
                helloCommandPreview = "{}",
                nextSteps = "next"
            )
        }
    }
}
