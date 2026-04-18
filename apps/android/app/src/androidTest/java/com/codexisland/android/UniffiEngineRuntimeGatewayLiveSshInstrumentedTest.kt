package com.codexisland.android

import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.codexisland.android.shell.runtime.UniffiEngineRuntimeGateway
import com.codexisland.android.shell.storage.HostProfile
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UniffiEngineRuntimeGatewayLiveSshInstrumentedTest {
    @Test
    fun liveGatewayConnectsToRealLinuxAppServer() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("live ssh args not provided", args.containsKey("ssh_target"))
        val sshTarget = requireArg(args, "ssh_target")
        val sshPublicKeyPkcs8 = requireArg(args, "ssh_public_key_pkcs8")
        val sshPrivateKeyPkcs8 = requireArg(args, "ssh_private_key_pkcs8")
        val context = ApplicationProvider.getApplicationContext<Context>()

        val gateway = UniffiEngineRuntimeGateway(
            clientName = "Codex Island Android",
            clientVersion = "0.1.0",
            nativeLibraryDir = context.applicationInfo.nativeLibraryDir
        )

        val host = HostProfile(
            id = "live-linux-host",
            displayName = "Linux 验收机",
            hostAddress = sshTarget,
            authToken = null,
            sshPassword = null,
            lastPairingCode = null,
            sshPublicKey = "",
            sshPublicKeyPkcs8 = sshPublicKeyPkcs8,
            sshPrivateKeyPkcs8 = sshPrivateKeyPkcs8
        )

        try {
            gateway.probe(host, "Android Companion", "", "")
            gateway.refresh()

            val deadline = SystemClock.elapsedRealtime() + 15_000L
            while (SystemClock.elapsedRealtime() < deadline) {
                val state = gateway.probe(host, "Android Companion", "", "")
                if (state.connection.contains("connected") &&
                    !state.threadListSummary.contains("还没有活动中的会话")
                ) {
                    return
                }
                SystemClock.sleep(500)
            }

            val finalState = gateway.probe(host, "Android Companion", "", "")
            throw AssertionError(
                "Live gateway did not connect in time. " +
                    "connection=${finalState.connection} diagnostics=${finalState.diagnostics} " +
                    "lastError=${finalState.lastError} threadList=${finalState.threadListSummary}"
            )
        } finally {
            gateway.close()
        }
    }

    private fun requireArg(args: android.os.Bundle, key: String): String =
        args.getString(key)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Missing instrumentation argument: $key")
}
