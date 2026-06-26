//! Build-time helper CLI (icon index, SVG rasterization, etc.).

#[path = "../helper/mod.rs"]
mod helper;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Err(e) = run(&args) {
        eprintln!("infer-core-helper: {e}");
        std::process::exit(1);
    }
}

fn run(args: &[String]) -> Result<(), String> {
    if args.len() < 2 || matches!(args[1].as_str(), "-h" | "--help" | "help") {
        print_usage();
        return Ok(());
    }

    match args[1].as_str() {
        "icon" => dispatch_icon(&args[2..]),
        other => Err(format!("unknown command: {other}")),
    }
}

fn dispatch_icon(args: &[String]) -> Result<(), String> {
    let Some(sub) = args.first() else {
        helper::icon_index_build::print_usage();
        helper::icon_index_convert::print_usage();
        helper::icon_rasterize_cli::print_usage();
        return Ok(());
    };

    match sub.as_str() {
        "index-build" => helper::icon_index_build::run(&args[1..]),
        "index-convert" => helper::icon_index_convert::run(&args[1..]),
        "rasterize-svg" => helper::icon_rasterize_cli::run(&args[1..]).map_err(|e| e.to_string()),
        "-h" | "--help" | "help" => {
            helper::icon_index_build::print_usage();
            helper::icon_index_convert::print_usage();
            helper::icon_rasterize_cli::print_usage();
            Ok(())
        }
        other => Err(format!("unknown icon subcommand: {other}")),
    }
}

fn print_usage() {
    eprintln!("Usage: infer-core-helper <command> [options]");
    eprintln!();
    eprintln!("Commands:");
    eprintln!("  icon index-build     Build icons.bundled embedding index from PNG templates");
    eprintln!("  icon index-convert   Convert fp32 embedding index to int8 (no re-embedding)");
    eprintln!("  icon rasterize-svg   Rasterize SVG icon templates to PNG");
    eprintln!();
    helper::icon_index_build::print_usage();
    eprintln!();
    helper::icon_index_convert::print_usage();
    eprintln!();
    helper::icon_rasterize_cli::print_usage();
}
