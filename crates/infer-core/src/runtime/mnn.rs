use mnn::schedule::{ForwardType, ScheduleConfig};

use super::RuntimeConfig;

pub fn schedule_config(config: &RuntimeConfig) -> ScheduleConfig {
    let mnn_cfg = config.mnn_config();
    let mut sc = ScheduleConfig::new();
    sc.set_type(parse_forward_type(&mnn_cfg.backend));
    if let Some(n) = mnn_cfg.num_thread {
        sc.set_num_threads(n as i32);
    }
    sc
}

fn parse_forward_type(backend: &str) -> ForwardType {
    backend.parse().unwrap_or(ForwardType::CPU)
}
