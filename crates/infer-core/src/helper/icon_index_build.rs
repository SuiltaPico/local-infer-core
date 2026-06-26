//! Build icons.bundled.v1.* embedding index from PNG templates.

use std::collections::{BTreeSet, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

use image::DynamicImage;
use infer_core_lib::embed::preprocess::template_png_to_rgb256;
use infer_core_lib::embed::{EmbedEngine, EMBED_DIM, INPUT_SIZE};
use infer_core_lib::icon_index::{EmbeddingIndex, IndexStorageFormat};
use infer_core_lib::runtime::RuntimeConfig;
use rayon::prelude::*;

#[derive(Debug, Clone)]
struct PngJob {
    name: String,
    path: PathBuf,
}

pub fn run(args: &[String]) -> Result<(), String> {
    let mut png_dir: Option<PathBuf> = None;
    let mut vision_model: Option<PathBuf> = None;
    let mut out: Option<PathBuf> = None;
    let mut format = IndexStorageFormat::Int8;
    let mut template_size = 48u32;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--png-dir" => {
                i += 1;
                png_dir = Some(PathBuf::from(args.get(i).ok_or("--png-dir value")?));
            }
            "--vision-model" => {
                i += 1;
                vision_model = Some(PathBuf::from(args.get(i).ok_or("--vision-model value")?));
            }
            "--out" => {
                i += 1;
                out = Some(PathBuf::from(args.get(i).ok_or("--out value")?));
            }
            "--format" => {
                i += 1;
                format = IndexStorageFormat::parse(args.get(i).ok_or("--format value")?)
                    .map_err(|e| e.to_string())?;
            }
            "--template-size" => {
                i += 1;
                template_size = args
                    .get(i)
                    .ok_or("--template-size value")?
                    .parse()
                    .map_err(|_| "invalid --template-size")?;
            }
            "--help" | "-h" => {
                print_usage();
                return Ok(());
            }
            other => return Err(format!("unknown argument: {other}")),
        }
        i += 1;
    }

    let png_dir = png_dir.ok_or("missing --png-dir")?;
    let vision_model = vision_model.ok_or("missing --vision-model")?;
    let out = out.ok_or("missing --out")?;

    if !png_dir.is_dir() {
        return Err(format!("png dir not found: {}", png_dir.display()));
    }
    if !vision_model.is_file() {
        return Err(format!("vision model not found: {}", vision_model.display()));
    }

    let jobs = collect_png_jobs(&png_dir)?;
    let index = build_index(&jobs, &vision_model, template_size)?;
    index
        .save_as(&out, format)
        .map_err(|e| e.to_string())?;

    let namespaces: Vec<_> = index
        .names
        .iter()
        .filter_map(|name| name.split_once(':').map(|(ns, _)| ns))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    eprintln!(
        "wrote {} icons -> {} (format={}){}",
        index.count(),
        out.display(),
        format.index_format_label(),
        if namespaces.is_empty() {
            String::new()
        } else {
            format!(", namespaces: {}", namespaces.join(", "))
        }
    );
    Ok(())
}

pub fn print_usage() {
    eprintln!(
        "Usage: infer-core-helper icon index-build --png-dir DIR --vision-model PATH --out PATH [--format int8|f32] [--template-size 48]"
    );
}

fn collect_png_jobs(root: &Path) -> Result<Vec<PngJob>, String> {
    let mut namespace_dirs: Vec<(String, PathBuf)> = Vec::new();
    let mut root_pngs: Vec<PathBuf> = Vec::new();

    for entry in fs::read_dir(root).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.is_dir() {
            let Some(ns) = path.file_name().and_then(|s| s.to_str()) else {
                continue;
            };
            let pngs = list_png_files(&path)?;
            if !pngs.is_empty() {
                namespace_dirs.push((ns.to_string(), path));
            }
        } else if path.extension().is_some_and(|ext| ext == "png") {
            root_pngs.push(path);
        }
    }

    let mut jobs = Vec::new();
    if namespace_dirs.is_empty() {
        for path in root_pngs {
            jobs.push(PngJob {
                name: png_label(&path, None)?,
                path,
            });
        }
    } else {
        namespace_dirs.sort_by(|a, b| a.0.cmp(&b.0));
        for (namespace, dir) in namespace_dirs {
            for path in list_png_files(&dir)? {
                jobs.push(PngJob {
                    name: png_label(&path, Some(&namespace))?,
                    path,
                });
            }
        }
    }

    jobs.sort_by(|a, b| a.name.cmp(&b.name));
    let mut seen = HashSet::new();
    for job in &jobs {
        if !seen.insert(&job.name) {
            return Err(format!("duplicate icon label: {}", job.name));
        }
    }
    if jobs.is_empty() {
        return Err(format!(
            "no PNG files under {} (expected flat *.png or <namespace>/*.png)",
            root.display()
        ));
    }
    Ok(jobs)
}

fn list_png_files(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut paths: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| e.to_string())?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.is_file() && path.extension().is_some_and(|ext| ext == "png"))
        .collect();
    paths.sort();
    Ok(paths)
}

fn png_label(path: &Path, namespace: Option<&str>) -> Result<String, String> {
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| format!("invalid PNG file name: {}", path.display()))?;
    Ok(match namespace {
        Some(ns) => format!("{ns}:{stem}"),
        None => stem.to_string(),
    })
}

fn build_index(
    jobs: &[PngJob],
    vision_model: &Path,
    template_size: u32,
) -> Result<EmbeddingIndex, String> {
    let runtime = RuntimeConfig::from_env_or_default();
    let worker_count = if runtime.prefer_gpu_single_session() {
        1
    } else {
        std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4)
            .min(jobs.len())
            .max(1)
    };

    let errors: Mutex<Vec<String>> = Mutex::new(vec![]);
    let done = AtomicUsize::new(0);
    let total = jobs.len();
    let vision_model = vision_model.to_path_buf();

    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(worker_count)
        .build()
        .map_err(|e| e.to_string())?;

    let mut results: Vec<(usize, String, Vec<f32>)> = pool.install(|| {
        jobs.par_iter()
            .enumerate()
            .filter_map(|(idx, job)| {
                let result = embed_png(&job.path, &vision_model, template_size, &runtime);
                match result {
                    Ok(embedding) => {
                        let n = done.fetch_add(1, Ordering::Relaxed) + 1;
                        if n % 500 == 0 || n == total {
                            eprintln!("embedded {n}/{total}");
                        }
                        Some((idx, job.name.clone(), embedding))
                    }
                    Err(e) => {
                        errors
                            .lock()
                            .expect("errors mutex")
                            .push(format!("{}: {e}", job.path.display()));
                        None
                    }
                }
            })
            .collect()
    });

    eprintln!("releasing embedder sessions...");
    drop_thread_engines(&pool);

    let errors = errors.into_inner().expect("errors mutex");
    if !errors.is_empty() {
        return Err(format!(
            "embedding failed for {} file(s): {}",
            errors.len(),
            errors.join("; ")
        ));
    }

    results.sort_by_key(|(idx, _, _)| *idx);
    let mut names = Vec::with_capacity(results.len());
    let mut vectors = Vec::with_capacity(results.len() * EMBED_DIM);
    for (_, name, embedding) in results {
        names.push(name);
        vectors.extend(embedding);
    }

    EmbeddingIndex::from_float_vectors(EMBED_DIM as u32, names, vectors).map_err(|e| e.to_string())
}

thread_local! {
    static THREAD_ENGINE: Mutex<Option<(PathBuf, EmbedEngine)>> = Mutex::new(None);
}

fn drop_thread_engines(pool: &rayon::ThreadPool) {
    pool.broadcast(|_| {
        THREAD_ENGINE.with(|cell| {
            *cell.lock().expect("engine mutex") = None;
        });
    });
}

fn embed_png(
    path: &Path,
    vision_model: &Path,
    template_size: u32,
    runtime: &RuntimeConfig,
) -> Result<Vec<f32>, String> {
    THREAD_ENGINE.with(|cell| {
        let mut guard = cell.lock().map_err(|e| e.to_string())?;
        let needs_load = match guard.as_ref() {
            None => true,
            Some((path, _)) => path != vision_model,
        };
        if needs_load {
            *guard = Some((
                vision_model.to_path_buf(),
                EmbedEngine::load(vision_model, runtime).map_err(|e| e.to_string())?,
            ));
        }
        let engine = &mut guard.as_mut().unwrap().1;
        let img =
            image::open(path).map_err(|e| format!("open {}: {e}", path.display()))?;
        embed_image(&img, engine, template_size)
    })
}

fn embed_image(
    img: &DynamicImage,
    engine: &mut EmbedEngine,
    template_size: u32,
) -> Result<Vec<f32>, String> {
    let rgb = template_png_to_rgb256(img, template_size);
    debug_assert_eq!(rgb.dimensions(), (INPUT_SIZE, INPUT_SIZE));
    engine.embed_rgb256(&rgb).map_err(|e| e.to_string())
}
