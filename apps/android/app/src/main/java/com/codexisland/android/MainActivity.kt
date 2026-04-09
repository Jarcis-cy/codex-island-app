package com.codexisland.android

import android.os.Bundle
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import com.codexisland.android.databinding.ActivityMainBinding
import com.codexisland.android.shell.bootstrap.ShellBootstrapUiState
import com.codexisland.android.shell.bootstrap.ShellBootstrapViewModel

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    private val viewModel: ShellBootstrapViewModel by viewModels {
        ShellBootstrapViewModel.factory(applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.saveHostButton.setOnClickListener {
            viewModel.saveHostProfile(
                deviceName = binding.deviceNameEditText.text?.toString().orEmpty(),
                hostConnectionInput = binding.hostConnectionEditText.text?.toString().orEmpty(),
                hostDisplayName = binding.hostDisplayNameEditText.text?.toString().orEmpty(),
                authToken = binding.authTokenEditText.text?.toString().orEmpty(),
                pairingCode = binding.pairingCodeEditText.text?.toString().orEmpty()
            )
        }

        binding.refreshButton.setOnClickListener {
            viewModel.refreshRuntime()
        }

        binding.nextHostButton.setOnClickListener {
            viewModel.selectNextHost()
        }

        viewModel.uiState.observe(this, ::render)
    }

    private fun render(state: ShellBootstrapUiState) {
        if (!binding.deviceNameEditText.isFocused &&
            binding.deviceNameEditText.text?.toString() != state.deviceName
        ) {
            binding.deviceNameEditText.setText(state.deviceName)
        }

        val tokenText = binding.authTokenEditText.text?.toString()
        if (!binding.authTokenEditText.isFocused && tokenText != state.authToken) {
            binding.authTokenEditText.setText(state.authToken)
        }
        if (!binding.hostConnectionEditText.isFocused &&
            binding.hostConnectionEditText.text?.toString() != state.hostConnectionInput
        ) {
            binding.hostConnectionEditText.setText(state.hostConnectionInput)
        }
        if (!binding.hostDisplayNameEditText.isFocused &&
            binding.hostDisplayNameEditText.text?.toString() != state.hostDisplayName
        ) {
            binding.hostDisplayNameEditText.setText(state.hostDisplayName)
        }
        if (!binding.pairingCodeEditText.isFocused &&
            binding.pairingCodeEditText.text?.toString() != state.pairingCode
        ) {
            binding.pairingCodeEditText.setText(state.pairingCode)
        }

        binding.shellSubtitle.text = state.subtitle
        binding.runtimeStatusChip.text = state.runtimeStatus
        binding.activeHostSummaryValue.text = state.activeHostSummary
        binding.hostProfilesValue.text = state.hostProfilesSummary
        binding.engineStatusValue.text = state.engineStatus
        binding.bindingValue.text = state.bindingSurface
        binding.connectionValue.text = state.connection
        binding.queueValue.text = state.commandQueue
        binding.pairedDevicesValue.text = state.pairedDevices
        binding.reconnectValue.text = state.reconnect
        binding.diagnosticsValue.text = state.diagnostics
        binding.lastErrorValue.text = state.lastError
        binding.helloCommandPreviewValue.text = state.helloCommandPreview
        binding.pairStartPreviewValue.text = state.pairStartPreview
        binding.pairConfirmPreviewValue.text = state.pairConfirmPreview
        binding.reconnectPreviewValue.text = state.reconnectPreview
        binding.nextStepsValue.text = state.nextSteps
        binding.authTokenInputLayout.helperText = state.authTokenHelper
    }
}
