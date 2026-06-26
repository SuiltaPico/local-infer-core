//! Convert an on-disk icon embedding index between storage formats (no re-embedding).

use std::path::PathBuf;

use infer_core_lib::icon_index::{
    read_file_storage_format, EmbeddingIndex, IndexStorageFormat,
};

pub fn run(args: &[String]) -> Result<(), String> {
    let mut input: Option<PathBuf> = None;
    let mut out_int8: Option<PathBuf> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--in" => {
                i += 1;
                input = Some(PathBuf::from(args.get(i).ok_or("--in value")?));
            }
            "--out-int8" => {
                i += 1;
                out_int8 = Some(PathBuf::from(args.get(i).ok_or("--out-int8 value")?));
            }
            "--help" | "-h" => {
                print_usage();
                return Ok(());
            }
            other => return Err(format!("unknown argument: {other}")),
        }
        i += 1;
    }

    let input = input.ok_or("missing --in")?;
    let out_int8 = out_int8.ok_or("missing --out-int8")?;

    if !input.is_file() {
        return Err(format!("input index not found: {}", input.display()));
    }

    let source_format = read_file_storage_format(&input).map_err(|e| e.to_string())?;
    if source_format != IndexStorageFormat::F32 {
        return Err(format!(
            "input must be fp32 index (mcl2-v1), got {}",
            source_format.index_format_label()
        ));
    }

    let index = EmbeddingIndex::load(&input).map_err(|e| e.to_string())?;
    index
        .save_as(&out_int8, IndexStorageFormat::Int8)
        .map_err(|e| e.to_string())?;

    eprintln!(
        "converted {} icons: {} ({}) -> {} (mcl2-v2)",
        index.count(),
        input.display(),
        source_format.index_format_label(),
        out_int8.display()
    );
    Ok(())
}

pub fn print_usage() {
    eprintln!(
        "Usage: infer-core-helper icon index-convert --in FP32_INDEX --out-int8 INT8_INDEX"
    );
}
