use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EngineVersion {
    pub protocol: &'static str,
    pub engine: &'static str,
}

pub fn current_version() -> EngineVersion {
    EngineVersion {
        protocol: "v1",
        engine: env!("CARGO_PKG_VERSION"),
    }
}
