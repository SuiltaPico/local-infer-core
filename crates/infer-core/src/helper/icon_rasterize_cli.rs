use std::path::PathBuf;

#[path = "../icon_rasterize.rs"]
mod icon_rasterize;

use icon_rasterize::{IconRasterColor, RasterizeSvgOptions, rasterize_svg_icons};

pub fn run(args: &[String]) -> anyhow::Result<()> {
    let mut svg_dir: Option<PathBuf> = None;
    let mut out_dir: Option<PathBuf> = None;
    let mut size = 48u32;
    let mut color = IconRasterColor::Black;
    let mut jobs: Option<usize> = None;
    let mut skip_existing = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--svg-dir" => {
                i += 1;
                svg_dir = Some(PathBuf::from(
                    args.get(i)
                        .ok_or_else(|| anyhow::anyhow!("missing --svg-dir value"))?,
                ));
            }
            "--out-dir" => {
                i += 1;
                out_dir = Some(PathBuf::from(
                    args.get(i)
                        .ok_or_else(|| anyhow::anyhow!("missing --out-dir value"))?,
                ));
            }
            "--size" => {
                i += 1;
                size = args
                    .get(i)
                    .ok_or_else(|| anyhow::anyhow!("missing --size value"))?
                    .parse()
                    .map_err(|_| anyhow::anyhow!("invalid --size"))?;
            }
            "--color" => {
                i += 1;
                color = IconRasterColor::parse(
                    args.get(i)
                        .ok_or_else(|| anyhow::anyhow!("missing --color value"))?,
                )?;
            }
            "--jobs" => {
                i += 1;
                jobs = Some(
                    args.get(i)
                        .ok_or_else(|| anyhow::anyhow!("missing --jobs value"))?
                        .parse()
                        .map_err(|_| anyhow::anyhow!("invalid --jobs"))?,
                );
            }
            "--skip-existing" => skip_existing = true,
            "--help" | "-h" => {
                print_usage();
                return Ok(());
            }
            other => return Err(anyhow::anyhow!("unknown argument: {other}")),
        }
        i += 1;
    }

    let svg_dir = svg_dir.ok_or_else(|| anyhow::anyhow!("missing --svg-dir"))?;
    let out_dir = out_dir.ok_or_else(|| anyhow::anyhow!("missing --out-dir"))?;

    rasterize_svg_icons(&RasterizeSvgOptions {
        svg_dir,
        out_dir,
        size,
        color,
        jobs,
        skip_existing,
    })
}

pub fn print_usage() {
    eprintln!(
        "Usage: infer-core-helper icon rasterize-svg --svg-dir DIR --out-dir DIR [--size 48] [--color black|white] [--jobs N] [--skip-existing]"
    );
}
