package com.codexisland.android.shell.storage

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class ShellProfile(
    val deviceName: String,
    val authToken: String?,
)

interface ShellProfileStore {
    fun load(): ShellProfile
    fun save(profile: ShellProfile)
}

class SecureShellStore internal constructor(
    context: Context,
    private val cryptor: SecretCryptor = AndroidKeyStoreCryptor(),
) : ShellProfileStore {
    private val preferences: SharedPreferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun load(): ShellProfile {
        val deviceName = preferences.getString(KEY_DEVICE_NAME, null)?.let(::decryptSafely)
            ?: DEFAULT_DEVICE_NAME
        val authToken = preferences.getString(KEY_AUTH_TOKEN, null)?.let(::decryptSafely)

        return ShellProfile(
            deviceName = deviceName,
            authToken = authToken?.ifBlank { null }
        )
    }

    override fun save(profile: ShellProfile) {
        preferences.edit().apply {
            putString(KEY_DEVICE_NAME, cryptor.encrypt(profile.deviceName))
            if (profile.authToken.isNullOrBlank()) {
                remove(KEY_AUTH_TOKEN)
            } else {
                putString(KEY_AUTH_TOKEN, cryptor.encrypt(profile.authToken))
            }
        }.apply()
    }

    private fun decryptSafely(value: String): String? {
        return try {
            cryptor.decrypt(value)
        } catch (_: Throwable) {
            null
        }
    }

    private companion object {
        private const val PREFERENCES_NAME = "codex_island.android.shell"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_AUTH_TOKEN = "auth_token"
        private const val DEFAULT_DEVICE_NAME = "Android Companion"
    }
}

internal interface SecretCryptor {
    fun encrypt(value: String): String
    fun decrypt(value: String): String
}

internal class AndroidKeyStoreCryptor : SecretCryptor {
    override fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        return "${encode(iv)}:${encode(encrypted)}"
    }

    override fun decrypt(value: String): String {
        val (iv, encrypted) = value.split(":", limit = 2)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateKey(),
            GCMParameterSpec(GCM_TAG_LENGTH_BITS, decode(iv))
        )
        val decrypted = cipher.doFinal(decode(encrypted))
        return String(decrypted, StandardCharsets.UTF_8)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existingKey = (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.secretKey
        if (existingKey != null) {
            return existingKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun encode(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_WRAP)

    private fun decode(value: String): ByteArray =
        Base64.decode(value, Base64.NO_WRAP)

    private companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "codex_island.android.shell.key"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH_BITS = 128
    }
}
