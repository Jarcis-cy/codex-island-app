package com.codexisland.android.shell.runtime

import com.codexisland.android.shell.storage.HostProfile
import uniffi.codex_island_client.ClientRuntimeConfig
import uniffi.codex_island_client.EngineRuntime
import uniffi.codex_island_client.uniffiEnsureInitialized

data class EngineRuntimeProbeResult(
    val runtimeLinked: Boolean,
    val engineStatus: String,
    val bindingSurface: String,
    val connection: String,
    val commandQueue: String,
    val pairedDevices: String,
    val reconnect: String,
    val diagnostics: String,
    val lastError: String,
    val helloCommandPreview: String,
    val pairStartCommandPreview: String,
    val pairConfirmCommandPreview: String,
    val reconnectCommandPreview: String,
    val nextSteps: String,
)

interface EngineRuntimeGateway {
    fun probe(hostProfile: HostProfile?, deviceName: String): EngineRuntimeProbeResult
}

class UniffiEngineRuntimeGateway(
    private val clientName: String,
    private val clientVersion: String,
) : EngineRuntimeGateway {
    override fun probe(hostProfile: HostProfile?, deviceName: String): EngineRuntimeProbeResult {
        return try {
            uniffiEnsureInitialized()
            EngineRuntime(
                ClientRuntimeConfig(
                    clientName = clientName,
                    clientVersion = clientVersion,
                    authToken = hostProfile?.authToken
                )
            ).use { runtime ->
                runtime.requestConnection()
                runtime.enqueueGetSnapshot()
                val state = runtime.state()
                val snapshot = state.snapshot
                val pairingCode = hostProfile?.lastPairingCode ?: "PAIR-123"
                val pairStartPreview = hostProfile?.let {
                    runtime.pairStartCommandJson(deviceName, ANDROID_PLATFORM)
                } ?: "Select a host profile first."
                val pairConfirmPreview = hostProfile?.let {
                    runtime.pairConfirmCommandJson(pairingCode, deviceName, ANDROID_PLATFORM)
                } ?: "Select a host profile and pairing code first."
                val reconnectPreview = hostProfile?.let {
                    "Reconnect to ${it.displayName} via ${it.hostAddress}, auth=" +
                        if (it.authToken.isNullOrBlank()) "pending pairing" else "stored token"
                } ?: "Select a host profile first."

                EngineRuntimeProbeResult(
                    runtimeLinked = true,
                    engineStatus = "UniFFI runtime 已初始化，client=${runtime.clientName()} ${runtime.clientVersion()}",
                    bindingSurface = "surface ${runtime.bindingSurfaceVersion()}",
                    connection = state.connection.name.lowercase(),
                    commandQueue = "${state.pendingCommands.size} pending / in-flight=" +
                        (state.inFlightCommand?.kind?.name?.lowercase() ?: "none"),
                    pairedDevices = "${snapshot.pairedDevices.size} paired / host reports ${snapshot.health.pairedDeviceCount}",
                    reconnect = if (state.reconnect.reconnectPending) {
                        "pending, backoff=${state.reconnect.currentBackoffMs}ms"
                    } else {
                        "idle, shouldReconnect=${state.reconnect.shouldReconnect}"
                    },
                    diagnostics = "connect=${state.diagnostics.connectAttempts}, " +
                        "disconnect=${state.diagnostics.disconnectCount}, " +
                        "protocol=${state.diagnostics.protocolErrorCount}",
                    lastError = state.lastError?.message ?: "none",
                    helloCommandPreview = runtime.helloCommandJson().take(140),
                    pairStartCommandPreview = pairStartPreview.take(220),
                    pairConfirmCommandPreview = pairConfirmPreview.take(220),
                    reconnectCommandPreview = reconnectPreview,
                    nextSteps = "1. 接 transport 发送 pending commands。\n" +
                        "2. 把 host profile 绑定到 transport/foreground service。\n" +
                        "3. 用 app-server request/interrupt 串起 thread/chat。",
                )
            }
        } catch (throwable: Throwable) {
            EngineRuntimeProbeResult(
                runtimeLinked = false,
                engineStatus = "未能装载 Rust runtime",
                bindingSurface = "native library missing",
                connection = "disconnected",
                commandQueue = "0 pending",
                pairedDevices = "0 paired",
                reconnect = "idle",
                diagnostics = "等待集成 host transport",
                lastError = throwable.message ?: throwable::class.java.simpleName,
                helloCommandPreview = "{}",
                pairStartCommandPreview = hostProfile?.let {
                    "pair_start ${it.hostAddress} as $deviceName"
                } ?: "Select a host profile first.",
                pairConfirmCommandPreview = hostProfile?.let {
                    "pair_confirm ${it.lastPairingCode ?: "<pairing-code>"} for ${it.hostAddress}"
                } ?: "Select a host profile and pairing code first.",
                reconnectCommandPreview = hostProfile?.let {
                    "Reconnect entry point ready for ${it.displayName} (${it.hostAddress})"
                } ?: "Select a host profile first.",
                nextSteps = "1. 生成并打包 Android 可加载的 Rust dylib/so。\n" +
                    "2. 配置 transport 层把 JSON 命令送到 hostd。\n" +
                    "3. 复用当前 bootstrap store 和 viewmodel 继续接业务流。",
            )
        }
    }

    private companion object {
        private const val ANDROID_PLATFORM = "android"
    }
}
