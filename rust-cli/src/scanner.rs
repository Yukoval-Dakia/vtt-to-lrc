use std::collections::HashSet;
use std::fs;
use std::path::{Component, Path, PathBuf};

/// 默认最大扫描深度
pub const DEFAULT_MAX_DEPTH: usize = 10;

/// 递归扫描目录下的所有 VTT 文件
pub fn scan_directory_for_vtt(
    directory: &Path,
    max_depth: usize,
    warnings: &mut Vec<String>,
) -> Vec<PathBuf> {
    let mut files = Vec::new();

    if !directory.exists() {
        return files;
    }

    scan_recursive(directory, 1, max_depth, warnings, &mut files);
    files
}

/// 从一组路径中收集所有 VTT 文件
pub fn collect_vtt_from_paths(
    paths: &[PathBuf],
    max_depth: usize,
    warnings: &mut Vec<String>,
) -> Vec<PathBuf> {
    let mut collected = Vec::new();

    for path in paths {
        match fs::symlink_metadata(path) {
            Ok(metadata) => {
                let file_type = metadata.file_type();
                if file_type.is_dir() {
                    collected.extend(scan_directory_for_vtt(path, max_depth, warnings));
                } else if file_type.is_file() && is_vtt_path(path) {
                    collected.push(to_absolute_path(path));
                }
            }
            Err(error) => {
                warnings.push(format!(
                    "跳过无法访问的路径：{}（{}）",
                    path.display(),
                    error
                ));
            }
        }
    }

    let mut seen = HashSet::new();
    let mut unique_files = Vec::new();
    for path in collected {
        if seen.insert(path.clone()) {
            unique_files.push(path);
        }
    }

    unique_files
}

/// 将路径转为绝对路径，不解析符号链接
pub fn to_absolute_path(path: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(path)
    };

    normalize_path(&absolute)
}

/// 判断是否为 VTT 文件
pub fn is_vtt_path(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .map(|value| value.eq_ignore_ascii_case("vtt"))
        .unwrap_or(false)
}

fn scan_recursive(
    current_dir: &Path,
    current_depth: usize,
    max_depth: usize,
    warnings: &mut Vec<String>,
    collected: &mut Vec<PathBuf>,
) {
    if current_depth > max_depth {
        warnings.push(format!(
            "达到最大扫描深度限制 ({max_depth})，跳过目录：{}",
            current_dir.display()
        ));
        return;
    }

    let entries = match fs::read_dir(current_dir) {
        Ok(entries) => entries,
        Err(error) => {
            warnings.push(format!(
                "跳过不可访问目录：{}（{}）",
                current_dir.display(),
                error
            ));
            return;
        }
    };

    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                warnings.push(format!(
                    "跳过不可访问目录：{}（{}）",
                    current_dir.display(),
                    error
                ));
                continue;
            }
        };

        let path = entry.path();
        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) => {
                warnings.push(format!(
                    "跳过无法访问的路径：{}（{}）",
                    path.display(),
                    error
                ));
                continue;
            }
        };

        let file_type = metadata.file_type();
        if file_type.is_file() && is_vtt_path(&path) {
            collected.push(to_absolute_path(&path));
        } else if file_type.is_dir() {
            scan_recursive(&path, current_depth + 1, max_depth, warnings, collected);
        }
    }
}

fn normalize_path(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();

    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            Component::RootDir | Component::Prefix(_) | Component::Normal(_) => {
                normalized.push(component.as_os_str());
            }
        }
    }

    normalized
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io;
    use tempfile::tempdir;

    #[test]
    fn 收集文件和目录中的_vtt() -> io::Result<()> {
        let dir = tempdir()?;
        let nested = dir.path().join("nested");
        fs::create_dir_all(&nested)?;

        let file_a = dir.path().join("a.vtt");
        let file_b = nested.join("b.VTT");
        let file_c = dir.path().join("c.txt");

        fs::write(&file_a, "WEBVTT")?;
        fs::write(&file_b, "WEBVTT")?;
        fs::write(&file_c, "ignore")?;

        let mut warnings = Vec::new();
        let files = collect_vtt_from_paths(
            &[dir.path().to_path_buf(), file_a.clone()],
            DEFAULT_MAX_DEPTH,
            &mut warnings,
        );

        assert_eq!(warnings.len(), 0);
        assert_eq!(files.len(), 2);
        assert!(files.contains(&to_absolute_path(&file_a)));
        assert!(files.contains(&to_absolute_path(&file_b)));
        Ok(())
    }

    #[test]
    fn 超过最大深度时写入警告() -> io::Result<()> {
        let dir = tempdir()?;
        let level1 = dir.path().join("level1");
        let level2 = level1.join("level2");
        fs::create_dir_all(&level2)?;
        fs::write(level2.join("deep.vtt"), "WEBVTT")?;

        let mut warnings = Vec::new();
        let files = scan_directory_for_vtt(dir.path(), 1, &mut warnings);

        assert!(files.is_empty());
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("达到最大扫描深度限制"));
        Ok(())
    }

    #[test]
    fn 绝对路径会清理当前目录片段() {
        let current = std::env::current_dir().expect("当前目录应当可获取");
        let normalized = to_absolute_path(Path::new("./rust-cli/src/../src/main.rs"));

        assert_eq!(normalized, current.join("rust-cli/src/main.rs"));
    }
}
