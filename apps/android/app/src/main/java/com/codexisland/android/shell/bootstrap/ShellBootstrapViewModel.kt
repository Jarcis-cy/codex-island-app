package com.codexisland.android.shell.bootstrap

import android.content.Context
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.codexisland.android.shell.runtime.EngineRuntimeGateway
import com.codexisland.android.shell.runtime.UniffiEngineRuntimeGateway
import com.codexisland.android.shell.storage.SecureShellStore
import com.codexisland.android.shell.storage.ShellProfile
import com.codexisland.android.shell.storage.ShellProfileStore

class ShellBootstrapViewModel(
    private val profileStore: ShellProfileStore,
    private val runtimeGateway: EngineRuntimeGateway,
) : ViewModel() {
    private val _uiState = MutableLiveData(renderState(profileStore.load()))
    val uiState: LiveData<ShellBootstrapUiState> = _uiState

    fun saveShellProfile(deviceName: String, authToken: String) {
        val normalizedProfile = ShellProfile(
            deviceName = deviceName.trim().ifBlank { DEFAULT_DEVICE_NAME },
            authToken = authToken.trim().ifBlank { null }
        )
        profileStore.save(normalizedProfile)
        _uiState.value = renderState(normalizedProfile)
    }

    fun refreshRuntime() {
        _uiState.value = renderState(profileStore.load())
    }

    private fun renderState(profile: ShellProfile): ShellBootstrapUiState {
        val runtime = runtimeGateway.probe(profile.authToken)
        val runtimeState = if (runtime.runtimeLinked) "已接入" else "待接入"
        val helperText = if (profile.authToken.isNullOrBlank()) {
            "可留空。保存后会使用 Android Keystore 加密写入本地。"
        } else {
            "Token 已保存在 Android Keystore 保护的本地存储中。"
        }

        return ShellBootstrapUiState(
            deviceName = profile.deviceName,
            authToken = profile.authToken.orEmpty(),
            subtitle = "Android 直连壳已拆出基础分层，后续 pairing、thread list 和 chat 直接在此面板继续铺。",
            runtimeStatus = runtimeState,
            engineStatus = runtime.engineStatus,
            bindingSurface = runtime.bindingSurface,
            connection = runtime.connection,
            commandQueue = runtime.commandQueue,
            pairedDevices = runtime.pairedDevices,
            reconnect = runtime.reconnect,
            diagnostics = runtime.diagnostics,
            lastError = runtime.lastError,
            helloCommandPreview = runtime.helloCommandPreview,
            nextSteps = runtime.nextSteps,
            authTokenHelper = helperText
        )
    }

    companion object {
        private const val DEFAULT_DEVICE_NAME = "Android Companion"

        fun factory(context: Context): ViewModelProvider.Factory {
            val appContext = context.applicationContext
            return object : ViewModelProvider.Factory {
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    val store = SecureShellStore(appContext)
                    val gateway = UniffiEngineRuntimeGateway(
                        clientName = "Codex Island Android",
                        clientVersion = APP_VERSION
                    )
                    @Suppress("UNCHECKED_CAST")
                    return ShellBootstrapViewModel(store, gateway) as T
                }
            }
        }

        private const val APP_VERSION = "0.1.0"
    }
}
