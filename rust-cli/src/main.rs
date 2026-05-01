use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::PathBuf;
use std::process;

use vtt_to_lrc_rust::converter::{convert_files_parallel, default_worker_count};
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
    let target_files =
        collect_target_files(args, "警告: 路径不存在: ", "警告: 无法访问路径", "警告: ")?;

    if target_files.is_empty() {
        eprintln!(
            "未找到 VTT 文件。用法: cargo run --manifest-path rust-cli/Cargo.toml -- [file1.vtt file2.vtt ...]"
        );
        return Err(1);
    }

    let results =
        convert_files_parallel(&target_files, default_worker_count()).map_err(|error| {
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
    let target_files = collect_target_files(args, "路径不存在: ", "无法访问路径", "")?;

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

fn resolve_input_args(args: &[String]) -> Result<Vec<String>, i32> {
    if args.is_empty() {
        return Ok(Vec::new());
    }

    if args[0] != "--input-file" {
        return Ok(args.to_vec());
    }

    if args.len() != 2 {
        eprintln!("错误: --input-file 需要且只能提供一个文件路径");
        return Err(1);
    }

    let file_path = &args[1];
    let content = fs::read_to_string(file_path).map_err(|error| {
        eprintln!("错误: 无法读取输入文件 \"{file_path}\": {error}");
        3
    })?;

    Ok(content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect())
}

fn collect_target_files(
    args: &[String],
    missing_prefix: &str,
    access_prefix: &str,
    warning_prefix: &str,
) -> Result<Vec<PathBuf>, i32> {
    let resolved_args = resolve_input_args(args)?;

    if resolved_args.is_empty() {
        return collect_current_directory_vtt_files().map_err(|error| {
            eprintln!("错误: 无法扫描当前目录: {error}");
            3
        });
    }

    let mut warnings = Vec::new();
    let valid_paths: Vec<PathBuf> = resolved_args
        .iter()
        .filter_map(|arg| {
            let path = PathBuf::from(arg);
            match fs::symlink_metadata(&path) {
                Ok(_) => Some(path),
                Err(error) if error.kind() == ErrorKind::NotFound => {
                    eprintln!("{missing_prefix}{arg}");
                    None
                }
                Err(error) => {
                    eprintln!("{access_prefix} \"{arg}\": {error}");
                    None
                }
            }
        })
        .collect();

    let files = collect_vtt_from_paths(&valid_paths, DEFAULT_MAX_DEPTH, &mut warnings);
    for warning in warnings {
        eprintln!("{warning_prefix}{warning}");
    }

    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn 从_input_file_读取路径列表() {
        let dir = tempdir().expect("临时目录应当创建成功");
        let input_file = dir.path().join("paths.txt");
        fs::write(&input_file, "/tmp/a.vtt\n\n/tmp/b.vtt\n").expect("输入文件应当写入成功");

        let args = vec!["--input-file".to_string(), input_file.display().to_string()];
        let resolved = resolve_input_args(&args).expect("应当成功读取输入文件");

        assert_eq!(resolved, vec!["/tmp/a.vtt", "/tmp/b.vtt"]);
    }

    #[test]
    fn input_file_参数缺失时返回错误() {
        let args = vec!["--input-file".to_string()];

        let error = resolve_input_args(&args).expect_err("应当返回错误");

        assert_eq!(error, 1);
    }
}
