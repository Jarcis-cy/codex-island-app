use std::env;

use codex_island_hostd::codex_app_server_command;

fn main() {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("--version") => {
            println!("{}", env!("CARGO_PKG_VERSION"));
        }
        Some("print-app-server-command") => {
            let shell = args.next().unwrap_or_else(|| "/bin/zsh".to_string());
            let config = codex_app_server_command(shell.as_ref());
            println!("{}", config.program.display());
            for arg in config.args {
                println!("{arg}");
            }
        }
        _ => {
            eprintln!("codex-island-hostd: scaffold only");
        }
    }
}
