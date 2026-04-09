use codex_island_proto::current_version;

pub fn engine_banner() -> String {
    let version = current_version();
    format!("codex-island-engine {} ({})", version.engine, version.protocol)
}
