use std::env;

fn main() {
    let version_flag = env::args().skip(1).any(|arg| arg == "--version");
    if version_flag {
        println!("{}", env!("CARGO_PKG_VERSION"));
        return;
    }

    eprintln!("codex-island-hostd: scaffold only");
}
