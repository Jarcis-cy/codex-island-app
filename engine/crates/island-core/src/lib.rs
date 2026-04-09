use std::collections::VecDeque;
use std::time::{SystemTime, UNIX_EPOCH};

use codex_island_proto::{
    AppServerHealth, AppServerLifecycleState, ClientCommand, EngineSnapshot, ErrorCode,
    HostCapabilities, HostHealthSnapshot, HostHealthStatus, HostPlatform, PairedDeviceRecord,
    ProtocolError, ServerEvent, current_version,
};
use serde_json::Value;

const INITIAL_RECONNECT_BACKOFF_MS: u64 = 1_000;
const MAX_RECONNECT_BACKOFF_MS: u64 = 30_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClientConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

#[derive(Debug, Clone, PartialEq)]
pub struct QueuedCommand {
    pub queue_id: u64,
    pub kind: CommandKind,
    pub command: ClientCommand,
    pub enqueued_at_ms: u64,
    pub last_sent_at_ms: Option<u64>,
    pub attempt_count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ReconnectState {
    pub should_reconnect: bool,
    pub reconnect_pending: bool,
    pub attempt_count: u32,
    pub current_backoff_ms: u64,
    pub next_backoff_ms: Option<u64>,
    pub last_scheduled_at_ms: Option<u64>,
    pub last_reconnected_at_ms: Option<u64>,
    pub last_disconnect_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ConnectionDiagnostics {
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

#[derive(Debug, Clone, PartialEq)]
pub struct ClientRuntimeState {
    pub connection: ClientConnectionState,
    pub snapshot: EngineSnapshot,
    pub last_error: Option<ProtocolError>,
    pub last_app_server_event: Option<Value>,
    pub authenticated: bool,
    pub auth_token: Option<String>,
    pub pending_commands: Vec<QueuedCommand>,
    pub in_flight_command: Option<QueuedCommand>,
    pub reconnect: ReconnectState,
    pub diagnostics: ConnectionDiagnostics,
}

#[derive(Debug, Clone)]
pub struct ClientRuntime {
    client_name: String,
    client_version: String,
    state: ClientRuntimeState,
    pending_commands: VecDeque<QueuedCommand>,
    next_queue_id: u64,
}

impl ClientRuntime {
    pub fn new(
        client_name: impl Into<String>,
        client_version: impl Into<String>,
        auth_token: Option<String>,
    ) -> Self {
        let authenticated = auth_token.is_some();
        Self {
            client_name: client_name.into(),
            client_version: client_version.into(),
            state: ClientRuntimeState {
                connection: ClientConnectionState::Disconnected,
                snapshot: default_snapshot(),
                last_error: None,
                last_app_server_event: None,
                authenticated,
                auth_token,
                pending_commands: Vec::new(),
                in_flight_command: None,
                reconnect: ReconnectState::default(),
                diagnostics: ConnectionDiagnostics::default(),
            },
            pending_commands: VecDeque::new(),
            next_queue_id: 1,
        }
    }

    pub fn client_name(&self) -> &str {
        &self.client_name
    }

    pub fn client_version(&self) -> &str {
        &self.client_version
    }

    pub fn auth_token(&self) -> Option<&str> {
        self.state.auth_token.as_deref()
    }

    pub fn replace_auth_token(&mut self, auth_token: Option<String>) {
        self.state.auth_token = auth_token;
        self.state.authenticated = self.state.auth_token.is_some();
    }

    pub fn binding_surface_version(&self) -> String {
        let version = current_version();
        format!("codex-island-engine {} ({})", version.engine, version.protocol)
    }

    pub fn state(&self) -> &ClientRuntimeState {
        &self.state
    }

    pub fn state_mut(&mut self) -> &mut ClientRuntimeState {
        &mut self.state
    }

    pub fn set_should_reconnect(&mut self, should_reconnect: bool) {
        self.state.reconnect.should_reconnect = should_reconnect;
        if !should_reconnect {
            self.state.reconnect.reconnect_pending = false;
            self.state.reconnect.next_backoff_ms = None;
        }
    }

    pub fn request_connection(&mut self) {
        let now = now_millis();
        self.state.reconnect.should_reconnect = true;
        self.state.connection = ClientConnectionState::Connecting;
        self.state.diagnostics.connect_attempts += 1;
        self.state.diagnostics.last_connect_requested_at_ms = Some(now);
        self.ensure_hello_queued(true);
    }

    pub fn activate_reconnect_now(&mut self) -> bool {
        if !self.state.reconnect.reconnect_pending {
            return false;
        }

        let now = now_millis();
        self.state.reconnect.reconnect_pending = false;
        self.state.reconnect.attempt_count += 1;
        self.state.reconnect.current_backoff_ms = self
            .state
            .reconnect
            .next_backoff_ms
            .unwrap_or(INITIAL_RECONNECT_BACKOFF_MS);
        self.state.diagnostics.connect_attempts += 1;
        self.state.diagnostics.last_connect_requested_at_ms = Some(now);
        self.state.connection = ClientConnectionState::Connecting;
        self.ensure_hello_queued(true);
        true
    }

    pub fn transport_disconnected(&mut self, reason: Option<String>) {
        let now = now_millis();
        self.state.connection = ClientConnectionState::Disconnected;
        self.state.diagnostics.disconnect_count += 1;
        self.state.diagnostics.transport_error_count += 1;
        self.state.diagnostics.last_disconnect_at_ms = Some(now);
        self.state.reconnect.last_disconnect_reason = reason.clone();
        self.state.diagnostics.last_error_message = reason;

        if let Some(in_flight) = self.state.in_flight_command.take()
            && should_retry_on_disconnect(in_flight.kind)
        {
            self.requeue_front(in_flight);
        }

        if self.state.reconnect.should_reconnect {
            let next_backoff = next_backoff_ms(self.state.reconnect.current_backoff_ms);
            self.state.reconnect.reconnect_pending = true;
            self.state.reconnect.next_backoff_ms = Some(next_backoff);
            self.state.reconnect.last_scheduled_at_ms = Some(now);
        }

        self.sync_queue_state();
    }

    pub fn hello_command(&mut self) -> ClientCommand {
        self.state.connection = ClientConnectionState::Connecting;
        ClientCommand::Hello {
            protocol_version: current_version().protocol.into(),
            client_name: self.client_name.clone(),
            client_version: self.client_version.clone(),
            auth_token: self.state.auth_token.clone(),
        }
    }

    pub fn get_snapshot_command(&self) -> ClientCommand {
        ClientCommand::GetSnapshot
    }

    pub fn pair_start_command(
        &self,
        device_name: impl Into<String>,
        client_platform: impl Into<String>,
    ) -> ClientCommand {
        ClientCommand::PairStart {
            device_name: device_name.into(),
            client_platform: client_platform.into(),
        }
    }

    pub fn pair_confirm_command(
        &self,
        pairing_code: impl Into<String>,
        device_name: impl Into<String>,
        client_platform: impl Into<String>,
    ) -> ClientCommand {
        ClientCommand::PairConfirm {
            pairing_code: pairing_code.into(),
            device_name: device_name.into(),
            client_platform: client_platform.into(),
        }
    }

    pub fn pair_revoke_command(&self, device_id: impl Into<String>) -> ClientCommand {
        ClientCommand::PairRevoke {
            device_id: device_id.into(),
        }
    }

    pub fn app_server_request_command(
        &self,
        request_id: impl Into<String>,
        method: impl Into<String>,
        params: Value,
    ) -> ClientCommand {
        ClientCommand::AppServerRequest {
            request_id: request_id.into(),
            method: method.into(),
            params,
        }
    }

    pub fn app_server_interrupt_command(
        &self,
        thread_id: impl Into<String>,
        turn_id: impl Into<String>,
    ) -> ClientCommand {
        ClientCommand::AppServerInterrupt {
            thread_id: thread_id.into(),
            turn_id: turn_id.into(),
        }
    }

    pub fn app_server_response_command(
        &self,
        request_id: impl Into<String>,
        result: Value,
    ) -> ClientCommand {
        ClientCommand::AppServerResponse {
            request_id: request_id.into(),
            result,
        }
    }

    pub fn enqueue_get_snapshot(&mut self) -> u64 {
        self.enqueue_command(self.get_snapshot_command())
    }

    pub fn enqueue_pair_start(
        &mut self,
        device_name: impl Into<String>,
        client_platform: impl Into<String>,
    ) -> u64 {
        self.enqueue_command(self.pair_start_command(device_name, client_platform))
    }

    pub fn enqueue_pair_confirm(
        &mut self,
        pairing_code: impl Into<String>,
        device_name: impl Into<String>,
        client_platform: impl Into<String>,
    ) -> u64 {
        self.enqueue_command(self.pair_confirm_command(pairing_code, device_name, client_platform))
    }

    pub fn enqueue_pair_revoke(&mut self, device_id: impl Into<String>) -> u64 {
        self.enqueue_command(self.pair_revoke_command(device_id))
    }

    pub fn enqueue_app_server_request(
        &mut self,
        request_id: impl Into<String>,
        method: impl Into<String>,
        params: Value,
    ) -> u64 {
        self.enqueue_command(self.app_server_request_command(request_id, method, params))
    }

    pub fn enqueue_app_server_interrupt(
        &mut self,
        thread_id: impl Into<String>,
        turn_id: impl Into<String>,
    ) -> u64 {
        self.enqueue_command(self.app_server_interrupt_command(thread_id, turn_id))
    }

    pub fn enqueue_app_server_response(
        &mut self,
        request_id: impl Into<String>,
        result: Value,
    ) -> u64 {
        self.enqueue_command(self.app_server_response_command(request_id, result))
    }

    pub fn pop_next_command(&mut self) -> Option<ClientCommand> {
        if self.state.in_flight_command.is_some() {
            return None;
        }

        let mut queued = self.pending_commands.pop_front()?;
        let now = now_millis();
        queued.attempt_count += 1;
        queued.last_sent_at_ms = Some(now);

        if queued.kind == CommandKind::Hello {
            self.state.connection = ClientConnectionState::Connecting;
            self.state.diagnostics.last_hello_sent_at_ms = Some(now);
        }

        let command = queued.command.clone();
        if tracks_in_flight(queued.kind) {
            self.state.in_flight_command = Some(queued);
        }
        self.sync_queue_state();
        Some(command)
    }

    pub fn apply_server_event(&mut self, event: ServerEvent) -> &ClientRuntimeState {
        let now = now_millis();
        match event {
            ServerEvent::HelloAck {
                protocol_version,
                daemon_version,
                host_id,
                authenticated,
            } => {
                self.clear_in_flight_if(|command| command.kind == CommandKind::Hello);
                self.state.connection = ClientConnectionState::Connected;
                self.state.authenticated = authenticated;
                self.state.snapshot.health.protocol_version = protocol_version;
                self.state.snapshot.health.daemon_version = daemon_version;
                self.state.snapshot.health.host_id = host_id;
                self.state.last_error = None;
                self.state.reconnect.reconnect_pending = false;
                self.state.reconnect.attempt_count = 0;
                self.state.reconnect.current_backoff_ms = 0;
                self.state.reconnect.next_backoff_ms = None;
                self.state.reconnect.last_reconnected_at_ms = Some(now);
                self.state.diagnostics.successful_connects += 1;
                self.state.diagnostics.last_hello_ack_at_ms = Some(now);
            }
            ServerEvent::Snapshot { snapshot } => {
                self.clear_in_flight_if(|command| command.kind == CommandKind::GetSnapshot);
                self.state.connection = ClientConnectionState::Connected;
                self.state.snapshot = snapshot;
                self.state.last_error = None;
                self.state.diagnostics.last_snapshot_at_ms = Some(now);
            }
            ServerEvent::HostHealthChanged { health } => {
                self.state.connection = ClientConnectionState::Connected;
                self.state.snapshot.health = health;
            }
            ServerEvent::PairingStarted { pairing } => {
                self.clear_in_flight_if(|command| command.kind == CommandKind::PairStart);
                self.state.snapshot.active_pairing = Some(pairing);
            }
            ServerEvent::PairingCompleted { device, token, .. } => {
                self.clear_in_flight_if(|command| command.kind == CommandKind::PairConfirm);
                self.state.snapshot.active_pairing = None;
                upsert_device(&mut self.state.snapshot.paired_devices, device);
                self.state.auth_token = Some(token.bearer_token);
                self.state.authenticated = true;
                self.state.last_error = None;
            }
            ServerEvent::PairingRevoked { device_id } => {
                self.clear_in_flight_if(|command| command.kind == CommandKind::PairRevoke);
                self.state
                    .snapshot
                    .paired_devices
                    .retain(|device| device.device_id != device_id);
            }
            ServerEvent::AppServerEvent { payload, .. } => {
                self.state.connection = ClientConnectionState::Connected;
                self.state.last_app_server_event = Some(payload);
            }
            ServerEvent::AppServerResponse { request_id, .. } => {
                self.clear_in_flight_if(|command| {
                    matches!(
                        &command.command,
                        ClientCommand::AppServerRequest {
                            request_id: queued_id,
                            ..
                        } if queued_id == &request_id
                    ) || matches!(
                        &command.command,
                        ClientCommand::AppServerInterrupt { .. }
                    )
                });
                self.state.connection = ClientConnectionState::Connected;
                self.state.diagnostics.last_response_request_id = Some(request_id);
            }
            ServerEvent::Error { error } => {
                self.state.connection = classify_error(&error);
                self.state.last_error = Some(error.clone());
                self.state.diagnostics.last_error_at_ms = Some(now);
                self.state.diagnostics.last_error_message = Some(error.message.clone());
                match error.code {
                    ErrorCode::Unauthorized => self.state.diagnostics.auth_failures += 1,
                    ErrorCode::InvalidProtocolVersion | ErrorCode::AppServerProtocolError => {
                        self.state.diagnostics.protocol_error_count += 1;
                    }
                    ErrorCode::AppServerUnavailable | ErrorCode::Internal => {
                        self.state.diagnostics.transport_error_count += 1;
                    }
                    _ => {}
                }
                self.state.in_flight_command = None;
            }
        }

        self.sync_queue_state();
        &self.state
    }

    fn enqueue_command(&mut self, command: ClientCommand) -> u64 {
        let kind = command_kind(&command);
        let queue_id = self.next_queue_id;
        self.next_queue_id += 1;
        self.pending_commands.push_back(QueuedCommand {
            queue_id,
            kind,
            command,
            enqueued_at_ms: now_millis(),
            last_sent_at_ms: None,
            attempt_count: 0,
        });
        self.sync_queue_state();
        queue_id
    }

    fn ensure_hello_queued(&mut self, front: bool) {
        if self.pending_commands.iter().any(|command| command.kind == CommandKind::Hello)
            || self
                .state
                .in_flight_command
                .as_ref()
                .is_some_and(|command| command.kind == CommandKind::Hello)
        {
            self.sync_queue_state();
            return;
        }

        let queued = QueuedCommand {
            queue_id: self.next_queue_id,
            kind: CommandKind::Hello,
            command: self.hello_command(),
            enqueued_at_ms: now_millis(),
            last_sent_at_ms: None,
            attempt_count: 0,
        };
        self.next_queue_id += 1;
        if front {
            self.pending_commands.push_front(queued);
        } else {
            self.pending_commands.push_back(queued);
        }
        self.sync_queue_state();
    }

    fn requeue_front(&mut self, mut queued: QueuedCommand) {
        queued.last_sent_at_ms = None;
        self.pending_commands.push_front(queued);
        self.sync_queue_state();
    }

    fn clear_in_flight_if<F>(&mut self, predicate: F)
    where
        F: FnOnce(&QueuedCommand) -> bool,
    {
        if self
            .state
            .in_flight_command
            .as_ref()
            .is_some_and(predicate)
        {
            self.state.in_flight_command = None;
        }
    }

    fn sync_queue_state(&mut self) {
        self.state.pending_commands = self.pending_commands.iter().cloned().collect();
    }
}

fn default_snapshot() -> EngineSnapshot {
    let version = current_version();
    EngineSnapshot {
        health: HostHealthSnapshot {
            protocol_version: version.protocol.into(),
            daemon_version: version.engine.into(),
            host_id: "unknown-host".into(),
            hostname: "unknown".into(),
            platform: HostPlatform::Macos,
            status: HostHealthStatus::Starting,
            started_at: String::new(),
            observed_at: String::new(),
            app_server: AppServerHealth {
                state: AppServerLifecycleState::Stopped,
                launch_command: Vec::new(),
                cwd: None,
                pid: None,
                last_exit_code: None,
                last_error: None,
                restart_count: 0,
            },
            capabilities: HostCapabilities {
                pairing: true,
                app_server_bridge: true,
                transcript_fallback: true,
                reconnect_resume: true,
            },
            paired_device_count: 0,
        },
        active_pairing: None,
        paired_devices: Vec::new(),
        active_thread_id: None,
        active_turn_id: None,
    }
}

fn upsert_device(devices: &mut Vec<PairedDeviceRecord>, next: PairedDeviceRecord) {
    match devices.iter_mut().find(|device| device.device_id == next.device_id) {
        Some(existing) => *existing = next,
        None => devices.push(next),
    }
}

fn classify_error(error: &ProtocolError) -> ClientConnectionState {
    match error.code {
        ErrorCode::InvalidProtocolVersion | ErrorCode::Internal => ClientConnectionState::Error,
        _ => ClientConnectionState::Disconnected,
    }
}

fn command_kind(command: &ClientCommand) -> CommandKind {
    match command {
        ClientCommand::Hello { .. } => CommandKind::Hello,
        ClientCommand::GetSnapshot => CommandKind::GetSnapshot,
        ClientCommand::PairStart { .. } => CommandKind::PairStart,
        ClientCommand::PairConfirm { .. } => CommandKind::PairConfirm,
        ClientCommand::PairRevoke { .. } => CommandKind::PairRevoke,
        ClientCommand::AppServerRequest { .. } => CommandKind::AppServerRequest,
        ClientCommand::AppServerResponse { .. } => CommandKind::AppServerResponse,
        ClientCommand::AppServerInterrupt { .. } => CommandKind::AppServerInterrupt,
    }
}

fn should_retry_on_disconnect(kind: CommandKind) -> bool {
    matches!(
        kind,
        CommandKind::Hello
            | CommandKind::GetSnapshot
            | CommandKind::AppServerRequest
            | CommandKind::AppServerInterrupt
    )
}

fn tracks_in_flight(kind: CommandKind) -> bool {
    !matches!(kind, CommandKind::AppServerResponse)
}

fn next_backoff_ms(current: u64) -> u64 {
    if current == 0 {
        INITIAL_RECONNECT_BACKOFF_MS
    } else {
        (current.saturating_mul(2)).min(MAX_RECONNECT_BACKOFF_MS)
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use codex_island_proto::{
        AppServerHealth, AppServerLifecycleState, AuthToken, EngineSnapshot, HostCapabilities,
        HostHealthSnapshot, HostHealthStatus, HostPlatform, PairedDeviceRecord, PairingSession,
        PairingSessionStatus, ProtocolError, ServerEvent, current_version,
    };
    use serde_json::json;

    use super::{ClientConnectionState, ClientRuntime, CommandKind};

    #[test]
    fn hello_command_carries_client_identity_and_token() {
        let mut runtime = ClientRuntime::new("codex-island-android", "0.1.0", Some("secret".into()));

        let command = runtime.hello_command();

        assert_eq!(runtime.state().connection, ClientConnectionState::Connecting);
        assert_eq!(
            serde_json::to_value(command).expect("serialize hello"),
            json!({
                "type": "hello",
                "protocol_version": current_version().protocol,
                "client_name": "codex-island-android",
                "client_version": "0.1.0",
                "auth_token": "secret"
            })
        );
    }

    #[test]
    fn request_connection_queues_single_hello() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);

        runtime.request_connection();
        runtime.request_connection();

        assert_eq!(runtime.state().pending_commands.len(), 1);
        assert_eq!(runtime.state().pending_commands[0].kind, CommandKind::Hello);
        assert_eq!(runtime.state().diagnostics.connect_attempts, 2);
    }

    #[test]
    fn pop_next_command_moves_it_to_inflight() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        runtime.enqueue_get_snapshot();

        let command = runtime.pop_next_command();

        assert!(matches!(command, Some(codex_island_proto::ClientCommand::GetSnapshot)));
        assert!(runtime.state().pending_commands.is_empty());
        assert_eq!(
            runtime.state().in_flight_command.as_ref().map(|command| command.kind),
            Some(CommandKind::GetSnapshot)
        );
    }

    #[test]
    fn transport_disconnect_requeues_retryable_command_and_schedules_backoff() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        runtime.request_connection();
        let _ = runtime.pop_next_command();
        runtime.enqueue_app_server_request("req-1", "thread/list", json!({}));

        runtime.transport_disconnected(Some("socket EOF".into()));

        assert!(runtime.state().reconnect.reconnect_pending);
        assert_eq!(runtime.state().reconnect.next_backoff_ms, Some(1_000));
        assert_eq!(runtime.state().pending_commands[0].kind, CommandKind::Hello);
        assert_eq!(runtime.state().diagnostics.disconnect_count, 1);
    }

    #[test]
    fn activate_reconnect_now_promotes_pending_reconnect_to_new_hello_attempt() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        runtime.set_should_reconnect(true);
        runtime.transport_disconnected(Some("network lost".into()));

        let activated = runtime.activate_reconnect_now();

        assert!(activated);
        assert!(!runtime.state().reconnect.reconnect_pending);
        assert_eq!(runtime.state().reconnect.attempt_count, 1);
        assert_eq!(runtime.state().pending_commands[0].kind, CommandKind::Hello);
    }

    #[test]
    fn hello_ack_resets_reconnect_state_and_marks_connection_connected() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        runtime.request_connection();
        let _ = runtime.pop_next_command();
        runtime.transport_disconnected(Some("network lost".into()));
        runtime.activate_reconnect_now();
        let _ = runtime.pop_next_command();

        runtime.apply_server_event(ServerEvent::HelloAck {
            protocol_version: "v1".into(),
            daemon_version: "0.1.0".into(),
            host_id: "host-1".into(),
            authenticated: true,
        });

        assert_eq!(runtime.state().connection, ClientConnectionState::Connected);
        assert_eq!(runtime.state().reconnect.attempt_count, 0);
        assert!(!runtime.state().reconnect.reconnect_pending);
        assert_eq!(runtime.state().diagnostics.successful_connects, 1);
    }

    #[test]
    fn apply_snapshot_replaces_runtime_snapshot() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        let snapshot = sample_snapshot();

        runtime.apply_server_event(ServerEvent::Snapshot {
            snapshot: snapshot.clone(),
        });

        assert_eq!(runtime.state().connection, ClientConnectionState::Connected);
        assert_eq!(runtime.state().snapshot, snapshot);
    }

    #[test]
    fn pairing_completion_promotes_authentication_state() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        let sample = sample_snapshot();

        runtime.apply_server_event(ServerEvent::PairingCompleted {
            pairing: sample.active_pairing.expect("pairing"),
            device: sample.paired_devices[0].clone(),
            token: AuthToken {
                token_id: "token-1".into(),
                bearer_token: "bearer-1".into(),
                expires_at: None,
            },
        });

        assert_eq!(runtime.state().auth_token.as_deref(), Some("bearer-1"));
        assert!(runtime.state().authenticated);
        assert_eq!(runtime.state().snapshot.paired_devices.len(), 1);
    }

    #[test]
    fn error_event_tracks_diagnostics_and_clears_inflight() {
        let mut runtime = ClientRuntime::new("codex-island-swift", "0.1.0", None);
        runtime.request_connection();
        let _ = runtime.pop_next_command();

        runtime.apply_server_event(ServerEvent::Error {
            error: ProtocolError {
                code: codex_island_proto::ErrorCode::Unauthorized,
                message: "bad token".into(),
                retryable: Some(false),
                details: None,
            },
        });

        assert_eq!(runtime.state().connection, ClientConnectionState::Disconnected);
        assert_eq!(runtime.state().diagnostics.auth_failures, 1);
        assert!(runtime.state().in_flight_command.is_none());
    }

    fn sample_snapshot() -> EngineSnapshot {
        EngineSnapshot {
            health: HostHealthSnapshot {
                protocol_version: "v1".into(),
                daemon_version: "0.1.0".into(),
                host_id: "host-1".into(),
                hostname: "devbox".into(),
                platform: HostPlatform::Macos,
                status: HostHealthStatus::Ready,
                started_at: "2026-04-09T00:00:00Z".into(),
                observed_at: "2026-04-09T00:01:00Z".into(),
                app_server: AppServerHealth {
                    state: AppServerLifecycleState::Ready,
                    launch_command: vec![
                        "/bin/zsh".into(),
                        "-lc".into(),
                        "exec codex app-server --listen stdio://".into(),
                    ],
                    cwd: Some("/repo".into()),
                    pid: Some(42),
                    last_exit_code: None,
                    last_error: None,
                    restart_count: 0,
                },
                capabilities: HostCapabilities {
                    pairing: true,
                    app_server_bridge: true,
                    transcript_fallback: true,
                    reconnect_resume: true,
                },
                paired_device_count: 1,
            },
            active_pairing: Some(PairingSession {
                pairing_code: "ABC-123".into(),
                session_id: "pair-1".into(),
                status: PairingSessionStatus::Pending,
                expires_at: "2026-04-09T00:05:00Z".into(),
                device_name: Some("Pixel".into()),
            }),
            paired_devices: vec![PairedDeviceRecord {
                device_id: "device-1".into(),
                device_name: "Pixel".into(),
                platform: "android".into(),
                created_at: "2026-04-09T00:00:00Z".into(),
                last_seen_at: Some("2026-04-09T00:01:00Z".into()),
                last_ip: Some("192.168.1.20".into()),
            }],
            active_thread_id: Some("thread-1".into()),
            active_turn_id: Some("turn-1".into()),
        }
    }
}
