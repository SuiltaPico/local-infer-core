use mnn::schedule::{ForwardType, ScheduleConfig};

use super::RuntimeConfig;

pub fn schedule_config(config: &RuntimeConfig) -> ScheduleConfig {
    let mnn_cfg = config.mnn_config();
    let backend = config.resolved_mnn_backend();
    let mut sc = ScheduleConfig::new();
    sc.set_type(parse_forward_type(&backend));
    sc.set_backup_type(ForwardType::CPU);
    if let Some(n) = mnn_cfg.num_thread {
        sc.set_num_threads(n as i32);
    }
    sc
}

fn parse_forward_type(backend: &str) -> ForwardType {
    backend.parse().unwrap_or(ForwardType::CPU)
}
