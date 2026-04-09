package com.codexisland.android.shell.runtime

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
    val nextSteps: String,
)

interface EngineRuntimeGateway {
    fun probe(authToken: String?): EngineRuntimeProbeResult
}

class UniffiEngineRuntimeGateway(
    private val clientName: String,
    private val clientVersion: String,
) : EngineRuntimeGateway {
    override fun probe(authToken: String?): EngineRuntimeProbeResult {
        return try {
            uniffiEnsureInitialized()
            EngineRuntime(
                ClientRuntimeConfig(
                    clientName = clientName,
                    clientVersion = clientVersion,
                    authToken = authToken
                )
            ).use { runtime ->
                runtime.requestConnection()
                runtime.enqueueGetSnapshot()
                val state = runtime.state()
                val snapshot = state.snapshot

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
                    nextSteps = "1. 接 transport 发送 pending commands。\n" +
                        "2. 把 pairing form 绑定到 enqueuePairStart/Confirm。\n" +
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
                nextSteps = "1. 生成并打包 Android 可加载的 Rust dylib/so。\n" +
                    "2. 配置 transport 层把 JSON 命令送到 hostd。\n" +
                    "3. 复用当前 bootstrap store 和 viewmodel 继续接业务流。",
            )
        }
    }
}
