package com.codexisland.android.shell.storage

import org.junit.Assert.assertEquals
import org.junit.Test

class SecureShellStoreTest {
    @Test
    fun parseHostInputAcceptsQrPayload() {
        val parsed = SecureShellStore.parseHostInput(
            "codex-island://pair?addr=linux.tail.ts.net:7331&name=Linux%20Box&token=abc123&pairing_code=PAIR-777"
        )

        assertEquals("linux.tail.ts.net:7331", parsed.hostAddress)
        assertEquals("Linux Box", parsed.displayName)
        assertEquals("abc123", parsed.authToken)
        assertEquals("PAIR-777", parsed.pairingCode)
    }

    @Test
    fun parseHostInputAcceptsManualAddress() {
        val parsed = SecureShellStore.parseHostInput("macbook.tail.ts.net:7331")

        assertEquals("macbook.tail.ts.net:7331", parsed.hostAddress)
        assertEquals(null, parsed.displayName)
        assertEquals(null, parsed.authToken)
        assertEquals(null, parsed.pairingCode)
    }
}
