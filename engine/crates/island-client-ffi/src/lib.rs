use std::fmt;
use std::sync::{Arc, Mutex};

use codex_island_core::{
    ClientConnectionState as CoreConnectionState, ClientRuntime, CommandKind as CoreCommandKind,
    ConnectionDiagnostics as CoreConnectionDiagnostics, QueuedCommand as CoreQueuedCommand,
    ReconnectState as CoreReconnectState,
};
use codex_island_proto::{
    AppServerHealth as ProtoAppServerHealth,
    AppServerLifecycleState as ProtoAppServerLifecycleState, ClientCommand, EngineSnapshot,
    ErrorCode as ProtoErrorCode, HostCapabilities as ProtoHostCapabilities,
    HostHealthSnapshot as ProtoHostHealthSnapshot, HostHealthStatus as ProtoHostHealthStatus,
    HostPlatform as ProtoHostPlatform, PairedDeviceRecord as ProtoPairedDeviceRecord,
    PairingSession as ProtoPairingSession, PairingSessionStatus as ProtoPairingSessionStatus,
    ProtocolError as ProtoProtocolError, ServerEvent,
};
use serde_json::Value;

uniffi::setup_scaffolding!("codex_island_client");

#[derive(Debug, Clone, uniffi::Record)]
pub struct ClientRuntimeConfig {
    pub client_name: String,
    pub client_version: String,
    pub auth_token: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ClientConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HostPlatform {
    Macos,
    Linux,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum HostHealthStatus {
    Starting,
    Ready,
    Degraded,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AppServerLifecycleState {
    Stopped,
    Starting,
    Ready,
    Degraded,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PairingSessionStatus {
    Pending,
    Confirmed,
    Expired,
    Revoked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ErrorCode {
    InvalidProtocolVersion,
    Unauthorized,
    UnsupportedCommand,
    PairingRequired,
    PairingCodeExpired,
    DeviceNotFound,
    AppServerUnavailable,
    AppServerProtocolError,
    Internal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CommandKind {
    Hello,
    GetSnapshot,
    PairStart,
    PairConfirm,
    PairRevoke,
    AppServerRequest,
    AppServerResponse,
    AppServerInterrupt,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProtocolError {
    pub code: ErrorCode,
    pub message: String,
    pub retryable: Option<bool>,
    pub details_json: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HostCapabilities {
    pub pairing: bool,
    pub app_server_bridge: bool,
    pub transcript_fallback: bool,
    pub reconnect_resume: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct AppServerHealth {
    pub state: AppServerLifecycleState,
    pub launch_command: Vec<String>,
    pub cwd: Option<String>,
    pub pid: Option<u32>,
    pub last_exit_code: Option<i32>,
    pub last_error: Option<String>,
    pub restart_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct HostHealthSnapshot {
    pub protocol_version: String,
    pub daemon_version: String,
    pub host_id: String,
    pub hostname: String,
    pub platform: HostPlatform,
    pub status: HostHealthStatus,
    pub started_at: String,
    pub observed_at: String,
    pub app_server: AppServerHealth,
    pub capabilities: HostCapabilities,
    pub paired_device_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PairingSession {
    pub pairing_code: String,
    pub session_id: String,
    pub status: PairingSessionStatus,
    pub expires_at: String,
    pub device_name: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PairedDeviceRecord {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub created_at: String,
    pub last_seen_at: Option<String>,
    pub last_ip: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct EngineSnapshotRecord {
    pub health: HostHealthSnapshot,
    pub active_pairing: Option<PairingSession>,
    pub paired_devices: Vec<PairedDeviceRecord>,
    pub active_thread_id: Option<String>,
    pub active_turn_id: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct QueuedCommandRecord {
    pub queue_id: u64,
    pub kind: CommandKind,
    pub command_json: String,
    pub enqueued_at_ms: u64,
    pub last_sent_at_ms: Option<u64>,
    pub attempt_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ReconnectStateRecord {
    pub should_reconnect: bool,
    pub reconnect_pending: bool,
    pub attempt_count: u32,
    pub current_backoff_ms: u64,
    pub next_backoff_ms: Option<u64>,
    pub last_scheduled_at_ms: Option<u64>,
    pub last_reconnected_at_ms: Option<u64>,
    pub last_disconnect_reason: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ConnectionDiagnosticsRecord {
    pub connect_attempts: u32,
    pub successful_connects: u32,
    pub disconnect_count: u32,
    pub auth_failures: u32,
    pub protocol_error_count: u32,
    pub transport_error_count: u32,
    pub last_connect_requested_at_ms: Option<u64>,
    pub last_hello_sent_at_ms: Option<u64>,
    pub last_hello_ack_at_ms: Option<u64>,
    pub last_snapshot_at_ms: Option<u64>,
    pub last_disconnect_at_ms: Option<u64>,
    pub last_error_at_ms: Option<u64>,
    pub last_error_message: Option<String>,
    pub last_response_request_id: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct EngineRuntimeState {
    pub connection: ClientConnectionState,
    pub snapshot: EngineSnapshotRecord,
    pub last_error: Option<ProtocolError>,
    pub last_app_server_event_json: Option<String>,
    pub authenticated: bool,
    pub auth_token: Option<String>,
    pub pending_commands: Vec<QueuedCommandRecord>,
    pub in_flight_command: Option<QueuedCommandRecord>,
    pub reconnect: ReconnectStateRecord,
    pub diagnostics: ConnectionDiagnosticsRecord,
}

#[derive(Debug, Clone, uniffi::Error)]
pub enum ClientRuntimeError {
    InvalidJson(String),
    InvalidServerEvent(String),
}

impl fmt::Display for ClientRuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidJson(message) => write!(f, "invalid json: {message}"),
            Self::InvalidServerEvent(message) => write!(f, "invalid server event: {message}"),
        }
    }
}

impl std::error::Error for ClientRuntimeError {}

#[derive(uniffi::Object)]
pub struct EngineRuntime {
    inner: Mutex<ClientRuntime>,
}

#[uniffi::export]
impl EngineRuntime {
    #[uniffi::constructor]
    pub fn new(config: ClientRuntimeConfig) -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(ClientRuntime::new(
                config.client_name,
                config.client_version,
                config.auth_token,
            )),
        })
    }

    pub fn binding_surface_version(&self) -> String {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .binding_surface_version()
    }

    pub fn client_name(&self) -> String {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .client_name()
            .to_owned()
    }

    pub fn client_version(&self) -> String {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .client_version()
            .to_owned()
    }

    pub fn auth_token(&self) -> Option<String> {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .auth_token()
            .map(ToOwned::to_owned)
    }

    pub fn replace_auth_token(&self, auth_token: Option<String>) {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .replace_auth_token(auth_token);
    }

    pub fn set_should_reconnect(&self, should_reconnect: bool) {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .set_should_reconnect(should_reconnect);
    }

    pub fn request_connection(&self) -> EngineRuntimeState {
        let mut runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        runtime.request_connection();
        runtime_state(runtime.state())
    }

    pub fn activate_reconnect_now(&self) -> bool {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .activate_reconnect_now()
    }

    pub fn transport_disconnected(&self, reason: Option<String>) -> EngineRuntimeState {
        let mut runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        runtime.transport_disconnected(reason);
        runtime_state(runtime.state())
    }

    pub fn state(&self) -> EngineRuntimeState {
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        runtime_state(runtime.state())
    }

    pub fn hello_command_json(&self) -> String {
        let mut runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        serialize_command(runtime.hello_command())
    }

    pub fn get_snapshot_command_json(&self) -> String {
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        serialize_command(runtime.get_snapshot_command())
    }

    pub fn enqueue_get_snapshot(&self) -> u64 {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_get_snapshot()
    }

    pub fn pair_start_command_json(&self, device_name: String, client_platform: String) -> String {
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        serialize_command(runtime.pair_start_command(device_name, client_platform))
    }

    pub fn enqueue_pair_start(&self, device_name: String, client_platform: String) -> u64 {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_pair_start(device_name, client_platform)
    }

    pub fn pair_confirm_command_json(
        &self,
        pairing_code: String,
        device_name: String,
        client_platform: String,
    ) -> String {
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        serialize_command(runtime.pair_confirm_command(pairing_code, device_name, client_platform))
    }

    pub fn enqueue_pair_confirm(
        &self,
        pairing_code: String,
        device_name: String,
        client_platform: String,
    ) -> u64 {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_pair_confirm(pairing_code, device_name, client_platform)
    }

    pub fn pair_revoke_command_json(&self, device_id: String) -> String {
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        serialize_command(runtime.pair_revoke_command(device_id))
    }

    pub fn enqueue_pair_revoke(&self, device_id: String) -> u64 {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_pair_revoke(device_id)
    }

    pub fn app_server_request_command_json(
        &self,
        request_id: String,
        method: String,
        params_json: String,
    ) -> Result<String, ClientRuntimeError> {
        let params: Value = serde_json::from_str(&params_json)
            .map_err(|error| ClientRuntimeError::InvalidJson(error.to_string()))?;
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        Ok(serialize_command(
            runtime.app_server_request_command(request_id, method, params),
        ))
    }

    pub fn enqueue_app_server_request(
        &self,
        request_id: String,
        method: String,
        params_json: String,
    ) -> Result<u64, ClientRuntimeError> {
        let params: Value = serde_json::from_str(&params_json)
            .map_err(|error| ClientRuntimeError::InvalidJson(error.to_string()))?;
        Ok(self
            .inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_app_server_request(request_id, method, params))
    }

    pub fn app_server_response_command_json(
        &self,
        request_id: String,
        result_json: String,
    ) -> Result<String, ClientRuntimeError> {
        let result: Value = serde_json::from_str(&result_json)
            .map_err(|error| ClientRuntimeError::InvalidJson(error.to_string()))?;
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        Ok(serialize_command(
            runtime.app_server_response_command(request_id, result),
        ))
    }

    pub fn enqueue_app_server_response(
        &self,
        request_id: String,
        result_json: String,
    ) -> Result<u64, ClientRuntimeError> {
        let result: Value = serde_json::from_str(&result_json)
            .map_err(|error| ClientRuntimeError::InvalidJson(error.to_string()))?;
        Ok(self
            .inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_app_server_response(request_id, result))
    }

    pub fn app_server_interrupt_command_json(&self, thread_id: String, turn_id: String) -> String {
        let runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        serialize_command(runtime.app_server_interrupt_command(thread_id, turn_id))
    }

    pub fn enqueue_app_server_interrupt(&self, thread_id: String, turn_id: String) -> u64 {
        self.inner
            .lock()
            .expect("engine runtime mutex poisoned")
            .enqueue_app_server_interrupt(thread_id, turn_id)
    }

    pub fn pop_next_command_json(&self) -> Option<String> {
        let mut runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        runtime.pop_next_command().map(serialize_command)
    }

    pub fn apply_server_event_json(
        &self,
        event_json: String,
    ) -> Result<EngineRuntimeState, ClientRuntimeError> {
        let event: ServerEvent = serde_json::from_str(&event_json)
            .map_err(|error| ClientRuntimeError::InvalidServerEvent(error.to_string()))?;
        let mut runtime = self.inner.lock().expect("engine runtime mutex poisoned");
        Ok(runtime_state(runtime.apply_server_event(event)))
    }
}

fn serialize_command(command: ClientCommand) -> String {
    serde_json::to_string(&command).expect("client command should always serialize")
}

fn runtime_state(state: &codex_island_core::ClientRuntimeState) -> EngineRuntimeState {
    EngineRuntimeState {
        connection: state.connection.into(),
        snapshot: state.snapshot.clone().into(),
        last_error: state.last_error.clone().map(Into::into),
        last_app_server_event_json: state
            .last_app_server_event
            .as_ref()
            .map(|payload| serde_json::to_string(payload).expect("event payload should serialize")),
        authenticated: state.authenticated,
        auth_token: state.auth_token.clone(),
        pending_commands: state
            .pending_commands
            .iter()
            .cloned()
            .map(Into::into)
            .collect(),
        in_flight_command: state.in_flight_command.clone().map(Into::into),
        reconnect: state.reconnect.clone().into(),
        diagnostics: state.diagnostics.clone().into(),
    }
}

impl From<CoreConnectionState> for ClientConnectionState {
    fn from(value: CoreConnectionState) -> Self {
        match value {
            CoreConnectionState::Disconnected => Self::Disconnected,
            CoreConnectionState::Connecting => Self::Connecting,
            CoreConnectionState::Connected => Self::Connected,
            CoreConnectionState::Error => Self::Error,
        }
    }
}

impl From<ProtoHostPlatform> for HostPlatform {
    fn from(value: ProtoHostPlatform) -> Self {
        match value {
            ProtoHostPlatform::Macos => Self::Macos,
            ProtoHostPlatform::Linux => Self::Linux,
        }
    }
}

impl From<ProtoHostHealthStatus> for HostHealthStatus {
    fn from(value: ProtoHostHealthStatus) -> Self {
        match value {
            ProtoHostHealthStatus::Starting => Self::Starting,
            ProtoHostHealthStatus::Ready => Self::Ready,
            ProtoHostHealthStatus::Degraded => Self::Degraded,
            ProtoHostHealthStatus::Failed => Self::Failed,
        }
    }
}

impl From<ProtoAppServerLifecycleState> for AppServerLifecycleState {
    fn from(value: ProtoAppServerLifecycleState) -> Self {
        match value {
            ProtoAppServerLifecycleState::Stopped => Self::Stopped,
            ProtoAppServerLifecycleState::Starting => Self::Starting,
            ProtoAppServerLifecycleState::Ready => Self::Ready,
            ProtoAppServerLifecycleState::Degraded => Self::Degraded,
            ProtoAppServerLifecycleState::Failed => Self::Failed,
        }
    }
}

impl From<ProtoPairingSessionStatus> for PairingSessionStatus {
    fn from(value: ProtoPairingSessionStatus) -> Self {
        match value {
            ProtoPairingSessionStatus::Pending => Self::Pending,
            ProtoPairingSessionStatus::Confirmed => Self::Confirmed,
            ProtoPairingSessionStatus::Expired => Self::Expired,
            ProtoPairingSessionStatus::Revoked => Self::Revoked,
        }
    }
}

impl From<ProtoErrorCode> for ErrorCode {
    fn from(value: ProtoErrorCode) -> Self {
        match value {
            ProtoErrorCode::InvalidProtocolVersion => Self::InvalidProtocolVersion,
            ProtoErrorCode::Unauthorized => Self::Unauthorized,
            ProtoErrorCode::UnsupportedCommand => Self::UnsupportedCommand,
            ProtoErrorCode::PairingRequired => Self::PairingRequired,
            ProtoErrorCode::PairingCodeExpired => Self::PairingCodeExpired,
            ProtoErrorCode::DeviceNotFound => Self::DeviceNotFound,
            ProtoErrorCode::AppServerUnavailable => Self::AppServerUnavailable,
            ProtoErrorCode::AppServerProtocolError => Self::AppServerProtocolError,
            ProtoErrorCode::Internal => Self::Internal,
        }
    }
}

impl From<CoreCommandKind> for CommandKind {
    fn from(value: CoreCommandKind) -> Self {
        match value {
            CoreCommandKind::Hello => Self::Hello,
            CoreCommandKind::GetSnapshot => Self::GetSnapshot,
            CoreCommandKind::PairStart => Self::PairStart,
            CoreCommandKind::PairConfirm => Self::PairConfirm,
            CoreCommandKind::PairRevoke => Self::PairRevoke,
            CoreCommandKind::AppServerRequest => Self::AppServerRequest,
            CoreCommandKind::AppServerResponse => Self::AppServerResponse,
            CoreCommandKind::AppServerInterrupt => Self::AppServerInterrupt,
        }
    }
}

impl From<ProtoProtocolError> for ProtocolError {
    fn from(value: ProtoProtocolError) -> Self {
        Self {
            code: value.code.into(),
            message: value.message,
            retryable: value.retryable,
            details_json: value.details.map(|details| {
                serde_json::to_string(&details).expect("error details should serialize")
            }),
        }
    }
}

impl From<ProtoHostCapabilities> for HostCapabilities {
    fn from(value: ProtoHostCapabilities) -> Self {
        Self {
            pairing: value.pairing,
            app_server_bridge: value.app_server_bridge,
            transcript_fallback: value.transcript_fallback,
            reconnect_resume: value.reconnect_resume,
        }
    }
}

impl From<ProtoAppServerHealth> for AppServerHealth {
    fn from(value: ProtoAppServerHealth) -> Self {
        Self {
            state: value.state.into(),
            launch_command: value.launch_command,
            cwd: value.cwd,
            pid: value.pid,
            last_exit_code: value.last_exit_code,
            last_error: value.last_error,
            restart_count: value.restart_count,
        }
    }
}

impl From<ProtoHostHealthSnapshot> for HostHealthSnapshot {
    fn from(value: ProtoHostHealthSnapshot) -> Self {
        Self {
            protocol_version: value.protocol_version,
            daemon_version: value.daemon_version,
            host_id: value.host_id,
            hostname: value.hostname,
            platform: value.platform.into(),
            status: value.status.into(),
            started_at: value.started_at,
            observed_at: value.observed_at,
            app_server: value.app_server.into(),
            capabilities: value.capabilities.into(),
            paired_device_count: value.paired_device_count,
        }
    }
}

impl From<ProtoPairingSession> for PairingSession {
    fn from(value: ProtoPairingSession) -> Self {
        Self {
            pairing_code: value.pairing_code,
            session_id: value.session_id,
            status: value.status.into(),
            expires_at: value.expires_at,
            device_name: value.device_name,
        }
    }
}

impl From<ProtoPairedDeviceRecord> for PairedDeviceRecord {
    fn from(value: ProtoPairedDeviceRecord) -> Self {
        Self {
            device_id: value.device_id,
            device_name: value.device_name,
            platform: value.platform,
            created_at: value.created_at,
            last_seen_at: value.last_seen_at,
            last_ip: value.last_ip,
        }
    }
}

impl From<EngineSnapshot> for EngineSnapshotRecord {
    fn from(value: EngineSnapshot) -> Self {
        Self {
            health: value.health.into(),
            active_pairing: value.active_pairing.map(Into::into),
            paired_devices: value.paired_devices.into_iter().map(Into::into).collect(),
            active_thread_id: value.active_thread_id,
            active_turn_id: value.active_turn_id,
        }
    }
}

impl From<CoreQueuedCommand> for QueuedCommandRecord {
    fn from(value: CoreQueuedCommand) -> Self {
        Self {
            queue_id: value.queue_id,
            kind: value.kind.into(),
            command_json: serialize_command(value.command),
            enqueued_at_ms: value.enqueued_at_ms,
            last_sent_at_ms: value.last_sent_at_ms,
            attempt_count: value.attempt_count,
        }
    }
}

impl From<CoreReconnectState> for ReconnectStateRecord {
    fn from(value: CoreReconnectState) -> Self {
        Self {
            should_reconnect: value.should_reconnect,
            reconnect_pending: value.reconnect_pending,
            attempt_count: value.attempt_count,
            current_backoff_ms: value.current_backoff_ms,
            next_backoff_ms: value.next_backoff_ms,
            last_scheduled_at_ms: value.last_scheduled_at_ms,
            last_reconnected_at_ms: value.last_reconnected_at_ms,
            last_disconnect_reason: value.last_disconnect_reason,
        }
    }
}

impl From<CoreConnectionDiagnostics> for ConnectionDiagnosticsRecord {
    fn from(value: CoreConnectionDiagnostics) -> Self {
        Self {
            connect_attempts: value.connect_attempts,
            successful_connects: value.successful_connects,
            disconnect_count: value.disconnect_count,
            auth_failures: value.auth_failures,
            protocol_error_count: value.protocol_error_count,
            transport_error_count: value.transport_error_count,
            last_connect_requested_at_ms: value.last_connect_requested_at_ms,
            last_hello_sent_at_ms: value.last_hello_sent_at_ms,
            last_hello_ack_at_ms: value.last_hello_ack_at_ms,
            last_snapshot_at_ms: value.last_snapshot_at_ms,
            last_disconnect_at_ms: value.last_disconnect_at_ms,
            last_error_at_ms: value.last_error_at_ms,
            last_error_message: value.last_error_message,
            last_response_request_id: value.last_response_request_id,
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{ClientRuntimeConfig, EngineRuntime};

    #[test]
    fn hello_command_json_uses_runtime_identity() {
        let runtime = EngineRuntime::new(ClientRuntimeConfig {
            client_name: "codex-island-swift".into(),
            client_version: "0.1.0".into(),
            auth_token: Some("secret".into()),
        });

        let command: serde_json::Value =
            serde_json::from_str(&runtime.hello_command_json()).expect("decode hello");

        assert_eq!(
            command,
            json!({
                "type": "hello",
                "protocol_version": "v1",
                "client_name": "codex-island-swift",
                "client_version": "0.1.0",
                "auth_token": "secret"
            })
        );
        assert_eq!(runtime.state().connection, super::ClientConnectionState::Connecting);
    }

    #[test]
    fn request_connection_and_queue_expose_pending_hello() {
        let runtime = EngineRuntime::new(ClientRuntimeConfig {
            client_name: "codex-island-swift".into(),
            client_version: "0.1.0".into(),
            auth_token: None,
        });

        let state = runtime.request_connection();

        assert_eq!(state.pending_commands.len(), 1);
        assert_eq!(state.pending_commands[0].kind, super::CommandKind::Hello);
        assert_eq!(state.connection, super::ClientConnectionState::Connecting);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(
                &runtime.pop_next_command_json().expect("queued command")
            )
            .expect("decode queued hello"),
            json!({
                "type": "hello",
                "protocol_version": "v1",
                "client_name": "codex-island-swift",
                "client_version": "0.1.0",
                "auth_token": null
            })
        );
    }

    #[test]
    fn transport_disconnect_surfaces_reconnect_state() {
        let runtime = EngineRuntime::new(ClientRuntimeConfig {
            client_name: "codex-island-android".into(),
            client_version: "0.1.0".into(),
            auth_token: None,
        });
        runtime.request_connection();
        let _ = runtime.pop_next_command_json();

        let state = runtime.transport_disconnected(Some("socket EOF".into()));

        assert!(state.reconnect.reconnect_pending);
        assert_eq!(state.reconnect.next_backoff_ms, Some(1_000));
        assert_eq!(state.diagnostics.disconnect_count, 1);
    }

    #[test]
    fn apply_server_event_json_updates_snapshot_and_authentication() {
        let runtime = EngineRuntime::new(ClientRuntimeConfig {
            client_name: "codex-island-android".into(),
            client_version: "0.1.0".into(),
            auth_token: None,
        });

        let state = runtime
            .apply_server_event_json(
                json!({
                    "type": "pairing_completed",
                    "pairing": {
                        "pairing_code": "ABC-123",
                        "session_id": "pair-1",
                        "status": "confirmed",
                        "expires_at": "2026-04-09T00:05:00Z",
                        "device_name": "Pixel"
                    },
                    "device": {
                        "device_id": "device-1",
                        "device_name": "Pixel",
                        "platform": "android",
                        "created_at": "2026-04-09T00:00:00Z",
                        "last_seen_at": "2026-04-09T00:01:00Z",
                        "last_ip": "192.168.1.20"
                    },
                    "token": {
                        "token_id": "token-1",
                        "bearer_token": "bearer-1",
                        "expires_at": null
                    }
                })
                .to_string(),
            )
            .expect("apply pairing event");

        assert!(state.authenticated);
        assert_eq!(state.auth_token.as_deref(), Some("bearer-1"));
        assert_eq!(state.snapshot.paired_devices.len(), 1);
        assert!(state.snapshot.active_pairing.is_none());
    }
}
