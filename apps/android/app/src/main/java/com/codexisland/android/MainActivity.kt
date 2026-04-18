package com.codexisland.android

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import com.codexisland.android.databinding.ActivityMainBinding
import com.codexisland.android.shell.bootstrap.ShellBootstrapUiState
import com.codexisland.android.shell.bootstrap.ShellBootstrapViewModel

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private var connectionPanelExpanded = false
    private var debugPanelExpanded = false
    private val uiRefreshHandler = Handler(Looper.getMainLooper())
    private val uiRefreshRunnable = object : Runnable {
        override fun run() {
            viewModel.captureDraftForm(
                deviceName = binding.deviceNameEditText.text?.toString().orEmpty(),
                hostConnectionInput = binding.hostConnectionEditText.text?.toString().orEmpty(),
                hostDisplayName = binding.hostDisplayNameEditText.text?.toString().orEmpty(),
                authToken = binding.authTokenEditText.text?.toString().orEmpty(),
                sshPassword = binding.sshPasswordEditText.text?.toString().orEmpty(),
                pairingCode = binding.pairingCodeEditText.text?.toString().orEmpty(),
                message = binding.messageEditText.text?.toString().orEmpty(),
                userInputAnswer = binding.userInputAnswerEditText.text?.toString().orEmpty()
            )
            viewModel.refreshUiSnapshot()
            uiRefreshHandler.postDelayed(this, UI_REFRESH_INTERVAL_MS)
        }
    }

    private val viewModel: ShellBootstrapViewModel by viewModels {
        MainActivityTestOverrides.viewModelFactory
            ?: ShellBootstrapViewModel.factory(applicationContext)
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
                sshPassword = binding.sshPasswordEditText.text?.toString().orEmpty(),
                pairingCode = binding.pairingCodeEditText.text?.toString().orEmpty()
            )
        }
        binding.refreshButton.setOnClickListener {
            viewModel.refreshRuntime(
                deviceName = binding.deviceNameEditText.text?.toString().orEmpty(),
                pairingCode = binding.pairingCodeEditText.text?.toString().orEmpty()
            )
        }
        binding.toggleConnectionButton.setOnClickListener {
            connectionPanelExpanded = !connectionPanelExpanded
            render(viewModel.uiState.value ?: return@setOnClickListener)
        }
        binding.toggleDebugButton.setOnClickListener {
            debugPanelExpanded = !debugPanelExpanded
            render(viewModel.uiState.value ?: return@setOnClickListener)
        }
        binding.nextHostButton.setOnClickListener { viewModel.selectNextHost() }
        binding.generateSshKeyButton.setOnClickListener { viewModel.generateSshKeyPair() }
        binding.startThreadButton.setOnClickListener { viewModel.startThread() }
        binding.nextThreadButton.setOnClickListener { viewModel.selectNextThread() }
        binding.resumeThreadButton.setOnClickListener { viewModel.resumeThread() }
        binding.sendMessageButton.setOnClickListener {
            viewModel.sendMessage(binding.messageEditText.text?.toString().orEmpty())
        }
        binding.interruptThreadButton.setOnClickListener { viewModel.interruptThread() }
        binding.allowApprovalButton.setOnClickListener { viewModel.allowApproval() }
        binding.denyApprovalButton.setOnClickListener { viewModel.denyApproval() }
        binding.submitInputButton.setOnClickListener {
            viewModel.submitUserInput(binding.userInputAnswerEditText.text?.toString().orEmpty())
        }

        viewModel.uiState.observe(this, ::render)
    }

    override fun onStart() {
        super.onStart()
        uiRefreshHandler.post(uiRefreshRunnable)
    }

    override fun onStop() {
        uiRefreshHandler.removeCallbacks(uiRefreshRunnable)
        super.onStop()
    }

    private fun render(state: ShellBootstrapUiState) {
        val hasPendingApproval = state.approvalSummary.isNotBlank() && !state.approvalSummary.contains("当前没有待处理审批")
        val hasPendingUserInput = state.userInputSummary.isNotBlank() && !state.userInputSummary.contains("当前没有待补充输入")
        val shouldShowConnectionPanel = connectionPanelExpanded || state.activeHostSummary.contains("还没有保存主机")

        syncText(binding.deviceNameEditText.text?.toString(), state.deviceName, binding.deviceNameEditText.isFocused) {
            binding.deviceNameEditText.setText(it)
        }
        syncText(binding.authTokenEditText.text?.toString(), state.hostdAuthToken, binding.authTokenEditText.isFocused) {
            binding.authTokenEditText.setText(it)
        }
        syncText(binding.sshPasswordEditText.text?.toString(), state.sshPassword, binding.sshPasswordEditText.isFocused) {
            binding.sshPasswordEditText.setText(it)
        }
        syncText(binding.hostConnectionEditText.text?.toString(), state.hostConnectionInput, binding.hostConnectionEditText.isFocused) {
            binding.hostConnectionEditText.setText(it)
        }
        syncText(binding.hostDisplayNameEditText.text?.toString(), state.hostDisplayName, binding.hostDisplayNameEditText.isFocused) {
            binding.hostDisplayNameEditText.setText(it)
        }
        syncText(binding.pairingCodeEditText.text?.toString(), state.pairingCode, binding.pairingCodeEditText.isFocused) {
            binding.pairingCodeEditText.setText(it)
        }
        syncText(binding.messageEditText.text?.toString(), state.messageDraft, binding.messageEditText.isFocused) {
            binding.messageEditText.setText(it)
        }
        syncText(binding.userInputAnswerEditText.text?.toString(), state.userInputDraft, binding.userInputAnswerEditText.isFocused) {
            binding.userInputAnswerEditText.setText(it)
        }

        binding.shellSubtitle.text = state.subtitle
        binding.approvalCard.visibility = if (hasPendingApproval) android.view.View.VISIBLE else android.view.View.GONE
        binding.userInputCard.visibility = if (hasPendingUserInput) android.view.View.VISIBLE else android.view.View.GONE
        binding.connectionPanel.visibility = if (shouldShowConnectionPanel) android.view.View.VISIBLE else android.view.View.GONE
        binding.debugPanel.visibility = if (debugPanelExpanded) android.view.View.VISIBLE else android.view.View.GONE
        binding.toggleConnectionButton.setText(
            if (shouldShowConnectionPanel) R.string.connection_panel_hide_cta else R.string.connection_panel_cta
        )
        binding.toggleDebugButton.setText(
            if (debugPanelExpanded) R.string.debug_panel_hide_cta else R.string.debug_panel_cta
        )
        binding.hostConnectionInputLayout.helperText = state.hostConnectionHelper
        binding.authTokenInputLayout.hint = getString(R.string.hostd_auth_token_label)
        binding.authTokenInputLayout.helperText = state.hostdAuthTokenHelper
        binding.authTokenInputLayout.visibility = if (state.showHostdAuthToken) android.view.View.VISIBLE else android.view.View.GONE
        binding.sshPasswordInputLayout.helperText = state.sshPasswordHelper
        binding.sshPasswordInputLayout.visibility = if (state.showSshPassword) android.view.View.VISIBLE else android.view.View.GONE
        binding.pairingCodeInputLayout.visibility = if (state.showPairingCode) android.view.View.VISIBLE else android.view.View.GONE
        binding.generateSshKeyButton.visibility = if (state.showSshKeyTools) android.view.View.VISIBLE else android.view.View.GONE
        binding.sshKeyStatusValue.visibility = if (state.showSshKeyTools) android.view.View.VISIBLE else android.view.View.GONE
        binding.sshPublicKeyValue.visibility = if (state.showSshKeyTools) android.view.View.VISIBLE else android.view.View.GONE
        binding.sshInstallCommandValue.visibility = if (state.showSshKeyTools) android.view.View.VISIBLE else android.view.View.GONE
        binding.sshKeyStatusValue.text = state.sshKeyStatus
        binding.sshPublicKeyValue.text = state.sshPublicKey
        binding.sshInstallCommandValue.text = state.sshInstallCommand
        binding.runtimeStatusChip.text = state.runtimeStatus
        binding.activeHostSummaryValue.text = state.activeHostSummary
        binding.hostProfilesValue.text = state.hostProfilesSummary
        binding.threadListValue.text = state.threadListSummary
        binding.activeThreadValue.text = state.activeThreadSummary
        binding.chatTranscriptValue.text = state.chatTranscript
        binding.approvalValue.text = state.approvalSummary
        binding.userInputValue.text = state.userInputSummary
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
        binding.threadListPreviewValue.text = state.threadListPreview
        binding.threadStartPreviewValue.text = state.threadStartPreview
        binding.threadResumePreviewValue.text = state.threadResumePreview
        binding.turnStartPreviewValue.text = state.turnStartPreview
        binding.turnSteerPreviewValue.text = state.turnSteerPreview
        binding.interruptPreviewValue.text = state.interruptPreview
        binding.nextStepsValue.text = state.nextSteps
    }

    private fun syncText(current: String?, expected: String, isFocused: Boolean, update: (String) -> Unit) {
        if (!isFocused && current != expected) {
            update(expected)
        }
    }
}

object MainActivityTestOverrides {
    @Volatile
    var viewModelFactory: ViewModelProvider.Factory? = null
}

private const val UI_REFRESH_INTERVAL_MS = 1_000L
