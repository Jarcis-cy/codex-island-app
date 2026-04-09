package com.codexisland.android.shell.bootstrap

data class ShellBootstrapUiState(
    val deviceName: String,
    val authToken: String,
    val subtitle: String,
    val runtimeStatus: String,
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
    val authTokenHelper: String,
)
