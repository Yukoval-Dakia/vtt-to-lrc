use std::env;
use std::fs;
use std::path::PathBuf;
use std::process;

use vtt_to_lrc_rust::converter::{convert_files_parallel, DEFAULT_WORKER_COUNT};
use vtt_to_lrc_rust::scanner::{
    collect_vtt_from_paths, is_vtt_path, to_absolute_path, DEFAULT_MAX_DEPTH,
};

fn main() {
    match run() {
        Ok(()) => {}
        Err(code) => process::exit(code),
    }
}

fn run() -> Result<(), i32> {
    let args: Vec<String> = env::args().skip(1).collect();

    match args.split_first() {
        Some((command, rest)) if command == "scan" => run_scan(rest),
        Some((command, rest)) if command == "convert" => run_convert(rest),
        _ => run_convert(&args),
    }
}

fn run_convert(args: &[String]) -> Result<(), i32> {
    let target_files = if args.is_empty() {
        collect_current_directory_vtt_files().map_err(|error| {
            eprintln!("错误: 无法扫描当前目录: {error}");
            3
        })?
    } else {
        let mut warnings = Vec::new();
        let valid_paths: Vec<PathBuf> = args
            .iter()
            .filter_map(|arg| {
                let path = PathBuf::from(arg);
                match fs::symlink_metadata(&path) {
                    Ok(_) => Some(path),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                        eprintln!("警告: 路径不存在: {arg}");
                        None
                    }
                    Err(error) => {
                        eprintln!("警告: 无法访问路径 \"{arg}\": {error}");
                        None
                    }
                }
            })
            .collect();

        let files = collect_vtt_from_paths(&valid_paths, DEFAULT_MAX_DEPTH, &mut warnings);
        for warning in warnings {
            eprintln!("警告: {warning}");
        }
        files
    };

    if target_files.is_empty() {
        eprintln!(
            "未找到 VTT 文件。用法: cargo run --manifest-path rust-cli/Cargo.toml -- [file1.vtt file2.vtt ...]"
        );
        return Err(1);
    }

    let results = convert_files_parallel(&target_files, DEFAULT_WORKER_COUNT).map_err(|error| {
        eprintln!("错误: 转换过程中发生异常: {error}");
        4
    })?;

    let mut failures = 0;
    for result in results {
        if let Some(destination) = result.destination {
            println!("Converted: {}", destination.display());
        } else if let Some(error) = result.error {
            eprintln!("Failed: {} -> {}", result.source.display(), error);
            failures += 1;
        }
    }

    if failures > 0 {
        return Err(1);
    }

    Ok(())
}

fn run_scan(args: &[String]) -> Result<(), i32> {
    let target_files = if args.is_empty() {
        collect_current_directory_vtt_files().map_err(|error| {
            eprintln!("错误: 无法扫描当前目录: {error}");
            3
        })?
    } else {
        let mut warnings = Vec::new();
        let valid_paths: Vec<PathBuf> = args
            .iter()
            .filter_map(|arg| {
                let path = PathBuf::from(arg);
                match fs::symlink_metadata(&path) {
                    Ok(_) => Some(path),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                        eprintln!("路径不存在: {arg}");
                        None
                    }
                    Err(error) => {
                        eprintln!("无法访问路径 \"{arg}\": {error}");
                        None
                    }
                }
            })
            .collect();

        let files = collect_vtt_from_paths(&valid_paths, DEFAULT_MAX_DEPTH, &mut warnings);
        for warning in warnings {
            eprintln!("{warning}");
        }
        files
    };

    for file in target_files {
        println!("{}", file.display());
    }

    Ok(())
}

fn collect_current_directory_vtt_files() -> Result<Vec<PathBuf>, std::io::Error> {
    let mut files = Vec::new();
    for entry in fs::read_dir(".")? {
        let entry = entry?;
        let path = entry.path();
        if path.is_file() && is_vtt_path(&path) {
            files.push(to_absolute_path(&path));
        }
    }
    Ok(files)
}
