use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread::{self, JoinHandle};

use anyhow::{Context, Result, anyhow};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpawnConfig {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: Option<PathBuf>,
}

impl SpawnConfig {
    pub fn new(program: impl Into<PathBuf>) -> Self {
        Self {
            program: program.into(),
            args: Vec::new(),
            cwd: None,
        }
    }

    pub fn args<I, S>(mut self, args: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        self.args = args.into_iter().map(Into::into).collect();
        self
    }

    pub fn cwd(mut self, cwd: impl Into<PathBuf>) -> Self {
        self.cwd = Some(cwd.into());
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChildEvent {
    StdoutLine(String),
    StderrLine(String),
    Terminated(ExitMetadata),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExitMetadata {
    pub code: Option<i32>,
    pub success: bool,
}

impl ExitMetadata {
    fn from_status(status: ExitStatus) -> Self {
        Self {
            code: status.code(),
            success: status.success(),
        }
    }
}

pub struct ManagedChild {
    child: Child,
    stdin: Option<ChildStdin>,
    events: Receiver<ChildEvent>,
    stdout_thread: Option<JoinHandle<()>>,
    stderr_thread: Option<JoinHandle<()>>,
}

impl ManagedChild {
    pub fn spawn(config: &SpawnConfig) -> Result<Self> {
        let mut command = Command::new(&config.program);
        command.args(&config.args);
        if let Some(cwd) = &config.cwd {
            command.current_dir(cwd);
        }
        command.stdin(Stdio::piped());
        command.stdout(Stdio::piped());
        command.stderr(Stdio::piped());

        let mut child = command.spawn().with_context(|| {
            format!(
                "failed to spawn child process: {}",
                config.program.display()
            )
        })?;

        let stdin = child.stdin.take();
        let stdout = child.stdout.take().context("child stdout was not piped")?;
        let stderr = child.stderr.take().context("child stderr was not piped")?;

        let (sender, receiver) = mpsc::channel();
        let stdout_thread = spawn_line_reader(stdout, sender.clone(), StreamKind::Stdout);
        let stderr_thread = spawn_line_reader(stderr, sender, StreamKind::Stderr);

        Ok(Self {
            child,
            stdin,
            events: receiver,
            stdout_thread: Some(stdout_thread),
            stderr_thread: Some(stderr_thread),
        })
    }

    pub fn send_line(&mut self, line: &str) -> Result<()> {
        let stdin = self
            .stdin
            .as_mut()
            .ok_or_else(|| anyhow!("child stdin is closed"))?;
        stdin
            .write_all(line.as_bytes())
            .context("failed to write stdin payload")?;
        stdin
            .write_all(b"\n")
            .context("failed to write stdin newline")?;
        stdin.flush().context("failed to flush child stdin")?;
        Ok(())
    }

    pub fn close_stdin(&mut self) {
        self.stdin.take();
    }

    pub fn try_recv_event(&self) -> std::result::Result<ChildEvent, mpsc::TryRecvError> {
        self.events.try_recv()
    }

    pub fn recv_event(&self) -> std::result::Result<ChildEvent, mpsc::RecvError> {
        self.events.recv()
    }

    pub fn wait(&mut self) -> Result<ExitMetadata> {
        let status = self.child.wait().context("failed waiting for child")?;
        let metadata = ExitMetadata::from_status(status);
        self.join_reader_threads();
        Ok(metadata)
    }

    pub fn stop(&mut self) -> Result<ExitMetadata> {
        self.close_stdin();
        if self.child.try_wait()?.is_none() {
            self.child.kill().context("failed to terminate child")?;
        }
        self.wait()
    }

    fn join_reader_threads(&mut self) {
        if let Some(handle) = self.stdout_thread.take() {
            let _ = handle.join();
        }
        if let Some(handle) = self.stderr_thread.take() {
            let _ = handle.join();
        }
    }
}

impl Drop for ManagedChild {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

#[derive(Copy, Clone)]
enum StreamKind {
    Stdout,
    Stderr,
}

fn spawn_line_reader<R>(reader: R, sender: Sender<ChildEvent>, stream: StreamKind) -> JoinHandle<()>
where
    R: std::io::Read + Send + 'static,
{
    thread::spawn(move || {
        let mut reader = BufReader::new(reader);
        let mut buffer = Vec::new();

        loop {
            buffer.clear();
            match reader.read_until(b'\n', &mut buffer) {
                Ok(0) => break,
                Ok(_) => {
                    if buffer.last() == Some(&b'\n') {
                        buffer.pop();
                    }
                    if buffer.last() == Some(&b'\r') {
                        buffer.pop();
                    }
                    if buffer.is_empty() {
                        continue;
                    }
                    let line = String::from_utf8_lossy(&buffer).into_owned();
                    let event = match stream {
                        StreamKind::Stdout => ChildEvent::StdoutLine(line),
                        StreamKind::Stderr => ChildEvent::StderrLine(line),
                    };
                    if sender.send(event).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    })
}

pub fn codex_app_server_command(shell: &Path) -> SpawnConfig {
    SpawnConfig::new(shell).args(["-lc", "exec codex app-server --listen stdio://"])
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::time::SystemTime;
    use std::time::{Duration, Instant};

    use super::{ChildEvent, ManagedChild, SpawnConfig, codex_app_server_command};

    #[test]
    fn codex_command_uses_login_shell_stdio_contract() {
        let config = codex_app_server_command(Path::new("/bin/zsh"));
        assert_eq!(config.program, PathBuf::from("/bin/zsh"));
        assert_eq!(
            config.args,
            vec![
                "-lc".to_string(),
                "exec codex app-server --listen stdio://".to_string()
            ]
        );
        assert_eq!(config.cwd, None);
    }

    #[test]
    fn flushes_stdout_and_stderr_without_trailing_newline() {
        let mut child = ManagedChild::spawn(&SpawnConfig::new("/bin/sh").args([
            "-c",
            "printf 'stdout-no-newline'; printf 'stderr-no-newline' >&2",
        ]))
        .expect("spawn child");

        let status = child.wait().expect("wait for child");
        assert!(status.success);

        let events = collect_events(&child, Duration::from_millis(200));
        assert!(events.contains(&ChildEvent::StdoutLine("stdout-no-newline".to_string())));
        assert!(events.contains(&ChildEvent::StderrLine("stderr-no-newline".to_string())));
    }

    #[test]
    fn propagates_cwd_to_child_process() {
        let cwd = unique_temp_dir("hostd-cwd");
        let mut child = ManagedChild::spawn(
            &SpawnConfig::new("/bin/pwd")
                .args(std::iter::empty::<&str>())
                .cwd(&cwd),
        )
        .expect("spawn pwd");

        let status = child.wait().expect("wait for pwd");
        assert!(status.success);

        let events = collect_events(&child, Duration::from_millis(200));
        let actual = events
            .iter()
            .find_map(|event| match event {
                ChildEvent::StdoutLine(line) => Some(PathBuf::from(line)),
                _ => None,
            })
            .expect("pwd output");
        assert_eq!(
            fs::canonicalize(actual).expect("canonicalize actual cwd"),
            fs::canonicalize(&cwd).expect("canonicalize expected cwd")
        );
    }

    #[test]
    fn surfaces_non_zero_exit_code_for_failed_child() {
        let mut child = ManagedChild::spawn(
            &SpawnConfig::new("/bin/sh").args(["-c", "echo boom >&2; exit 17"]),
        )
        .expect("spawn failing child");

        let status = child.wait().expect("wait for failing child");
        assert_eq!(status.code, Some(17));
        assert!(!status.success);

        let events = collect_events(&child, Duration::from_millis(200));
        assert!(events.contains(&ChildEvent::StderrLine("boom".to_string())));
    }

    #[test]
    fn stop_terminates_long_running_child_and_closes_stdin() {
        let mut child = ManagedChild::spawn(
            &SpawnConfig::new("/bin/sh").args(["-c", "trap '' TERM; cat >/dev/null & wait"]),
        )
        .expect("spawn long-running child");

        child.send_line("hello").expect("write stdin");
        let status = child.stop().expect("stop child");
        assert!(!status.success);
    }

    fn collect_events(child: &ManagedChild, timeout: Duration) -> Vec<ChildEvent> {
        let deadline = Instant::now() + timeout;
        let mut events = Vec::new();

        loop {
            match child.try_recv_event() {
                Ok(event) => events.push(event),
                Err(std::sync::mpsc::TryRecvError::Empty) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => break,
            }
        }

        events
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .expect("system time before epoch")
            .as_nanos();
        let unique = format!("{prefix}-{}-{}", std::process::id(), nanos);
        path.push(unique);
        fs::create_dir_all(&path).expect("create temp dir");
        path
    }

    use std::path::Path;
}
