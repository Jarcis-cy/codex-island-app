package com.codexisland.android.shell.bootstrap

import android.content.Context
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.codexisland.android.shell.runtime.EngineRuntimeGateway
import com.codexisland.android.shell.runtime.UniffiEngineRuntimeGateway
import com.codexisland.android.shell.storage.HostProfile
import com.codexisland.android.shell.storage.HostProfileEditor
import com.codexisland.android.shell.storage.SecureShellStore
import com.codexisland.android.shell.storage.ShellProfile
import com.codexisland.android.shell.storage.ShellProfileStore

class ShellBootstrapViewModel(
    private val profileStore: ShellProfileStore,
    private val runtimeGateway: EngineRuntimeGateway,
    private val hostProfileEditor: HostProfileEditor? = null,
) : ViewModel() {
    private var draftHostConnectionInput: String = ""
    private var draftHostDisplayName: String = ""
    private var draftPairingCode: String = ""

    private val _uiState = MutableLiveData(renderState(profileStore.load()))
    val uiState: LiveData<ShellBootstrapUiState> = _uiState

    fun saveHostProfile(
        deviceName: String,
        hostConnectionInput: String,
        hostDisplayName: String,
        authToken: String,
        pairingCode: String,
    ) {
        val current = profileStore.load()
        val updated = hostProfileEditor?.upsertHost(
            current = current.copy(deviceName = normalizeDeviceName(deviceName)),
            rawConnectionInput = hostConnectionInput,
            explicitDisplayName = hostDisplayName,
            explicitAuthToken = authToken,
            pairingCode = pairingCode
        ) ?: current

        profileStore.save(updated)
        draftHostConnectionInput = updated.activeHost()?.hostAddress.orEmpty()
        draftHostDisplayName = updated.activeHost()?.displayName.orEmpty()
        draftPairingCode = updated.activeHost()?.lastPairingCode.orEmpty()
        _uiState.value = renderState(updated)
    }

    fun selectNextHost() {
        val current = profileStore.load()
        if (current.hosts.isEmpty()) {
            return
        }

        val currentIndex = current.hosts.indexOfFirst { it.id == current.activeHostId }.coerceAtLeast(0)
        val nextHost = current.hosts[(currentIndex + 1) % current.hosts.size]
        val updated = hostProfileEditor?.selectHost(current, nextHost.id) ?: current
        profileStore.save(updated)
        draftHostConnectionInput = nextHost.hostAddress
        draftHostDisplayName = nextHost.displayName
        draftPairingCode = nextHost.lastPairingCode.orEmpty()
        _uiState.value = renderState(updated)
    }

    fun refreshRuntime() {
        _uiState.value = renderState(profileStore.load())
    }

    private fun renderState(profile: ShellProfile): ShellBootstrapUiState {
        val activeHost = profile.activeHost()
        if (draftHostConnectionInput.isBlank()) {
            draftHostConnectionInput = activeHost?.hostAddress.orEmpty()
        }
        if (draftHostDisplayName.isBlank()) {
            draftHostDisplayName = activeHost?.displayName.orEmpty()
        }
        if (draftPairingCode.isBlank()) {
            draftPairingCode = activeHost?.lastPairingCode.orEmpty()
        }

        val runtime = runtimeGateway.probe(activeHost, profile.deviceName)
        val runtimeState = if (runtime.runtimeLinked) "已接入" else "待接入"
        val helperText = if (activeHost?.authToken.isNullOrBlank()) {
            "Auth token 可留空。若 QR payload 内含 token，会在保存 host 时一并写入 Keystore。"
        } else {
            "当前 host 已保存 auth token，可直接作为 reconnect 入口。"
        }

        return ShellBootstrapUiState(
            deviceName = profile.deviceName,
            hostConnectionInput = draftHostConnectionInput,
            hostDisplayName = draftHostDisplayName,
            authToken = activeHost?.authToken.orEmpty(),
            pairingCode = draftPairingCode,
            subtitle = "当前面板支持手动地址或粘贴 QR payload、保存多个 host profile、预备 pairing 命令，并提供 reconnect 入口。",
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
            pairStartPreview = runtime.pairStartCommandPreview,
            pairConfirmPreview = runtime.pairConfirmCommandPreview,
            reconnectPreview = runtime.reconnectCommandPreview,
            nextSteps = runtime.nextSteps,
            authTokenHelper = helperText,
            hostProfilesSummary = profile.hosts.summary(activeHost?.id),
            activeHostSummary = activeHost?.let(::describeHost)
                ?: "尚未保存 host profile。可输入 Tailscale 地址，例如 `macbook.tail.ts.net:7331`，或粘贴 `codex-island://...` QR payload。"
        )
    }

    private fun ShellProfile.activeHost(): HostProfile? {
        return hosts.firstOrNull { it.id == activeHostId } ?: hosts.firstOrNull()
    }

    private fun List<HostProfile>.summary(activeHostId: String?): String {
        if (isEmpty()) {
            return "No saved hosts yet."
        }

        return joinToString("\n") { host ->
            val marker = if (host.id == activeHostId) "• active" else "• saved"
            val authState = if (host.authToken.isNullOrBlank()) "pairing pending" else "paired token stored"
            "$marker ${host.displayName}  ${host.hostAddress}  [$authState]"
        }
    }

    private fun describeHost(host: HostProfile): String {
        val authState = if (host.authToken.isNullOrBlank()) "未配对" else "已保存 token"
        val pairing = host.lastPairingCode ?: "未记录 pairing code"
        return "${host.displayName}\n${host.hostAddress}\n$authState · $pairing"
    }

    private fun normalizeDeviceName(deviceName: String): String =
        deviceName.trim().ifBlank { DEFAULT_DEVICE_NAME }

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
                    return ShellBootstrapViewModel(store, gateway, store) as T
                }
            }
        }

        private const val APP_VERSION = "0.1.0"
    }
}
