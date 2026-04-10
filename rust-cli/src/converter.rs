use encoding_rs::mem::decode_latin1;
use encoding_rs::{GBK, WINDOWS_1252};
use rayon::prelude::*;
use rayon::ThreadPoolBuilder;
use regex::Regex;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use crate::scanner::{is_vtt_path, to_absolute_path};

/// 默认并发工作线程数
pub const DEFAULT_WORKER_COUNT: usize = 8;

/// 支持的编码类型
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EncodingType {
    Utf8,
    Ascii,
    Latin1,
    Windows1252,
    Gbk,
}

/// 单个文件转换结果
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConvertResult {
    pub source: PathBuf,
    pub destination: Option<PathBuf>,
    pub error: Option<String>,
}

impl ConvertResult {
    pub fn success(source: PathBuf, destination: PathBuf) -> Self {
        Self {
            source,
            destination: Some(destination),
            error: None,
        }
    }

    pub fn failure(source: PathBuf, error: String) -> Self {
        Self {
            source,
            destination: None,
            error: Some(error),
        }
    }

    pub fn is_success(&self) -> bool {
        self.error.is_none()
    }
}

/// 转换错误
#[derive(Debug, Eq, PartialEq)]
pub enum ConvertError {
    Io(String),
    Format(String),
}

impl fmt::Display for ConvertError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConvertError::Io(message) => write!(f, "{message}"),
            ConvertError::Format(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for ConvertError {}

/// 将 VTT 文本中的内联标签清理掉
pub fn clean_vtt_text(text: &str) -> String {
    let regex = tag_regex();
    regex.replace_all(text, "").into_owned()
}

/// 检查时间戳是否为严格的 HH:MM:SS.mmm 格式
pub fn is_valid_vtt_timestamp(timestamp: &str) -> bool {
    timestamp_regex().is_match(timestamp.trim())
}

/// 将 VTT 时间戳转换为 LRC 标签
pub fn vtt_time_to_lrc(timestamp: &str) -> Option<String> {
    let trimmed = timestamp.trim();
    if !is_valid_vtt_timestamp(trimmed) {
        return None;
    }

    let parts: Vec<&str> = trimmed.split(':').collect();
    if parts.len() != 3 {
        return None;
    }

    let hours = parts[0].parse::<u64>().ok()?;
    let minutes = parts[1].parse::<u64>().ok()?;
    let second_parts: Vec<&str> = parts[2].split('.').collect();
    if second_parts.len() != 2 {
        return None;
    }

    let seconds = second_parts[0].parse::<u64>().ok()?;
    let milliseconds = second_parts[1].parse::<u64>().ok()?;

    if minutes > 59 || seconds > 59 || milliseconds > 999 {
        return None;
    }

    let total_ms = (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
    let lrc_minutes = total_ms / 60_000;
    let lrc_seconds = (total_ms % 60_000) / 1000;
    let centiseconds = (total_ms % 1000) / 10;

    Some(format!(
        "[{lrc_minutes:02}:{lrc_seconds:02}.{centiseconds:02}]"
    ))
}

/// 检测文件编码
pub fn detect_encoding(bytes: &[u8]) -> EncodingType {
    if has_utf8_bom(bytes) || is_valid_utf8(bytes) {
        return EncodingType::Utf8;
    }

    if is_valid_ascii(bytes) {
        return EncodingType::Ascii;
    }

    if is_likely_gbk(bytes)
        && GBK
            .decode_without_bom_handling_and_without_replacement(bytes)
            .is_some()
    {
        return EncodingType::Gbk;
    }

    EncodingType::Latin1
}

/// 按既定优先级检测并解码内容
pub fn detect_and_decode(bytes: &[u8]) -> String {
    if has_utf8_bom(bytes) {
        return String::from_utf8(bytes[3..].to_vec())
            .unwrap_or_else(|_| String::from_utf8_lossy(&bytes[3..]).into_owned());
    }

    if is_valid_utf8(bytes) {
        return String::from_utf8(bytes.to_vec())
            .unwrap_or_else(|_| String::from_utf8_lossy(bytes).into_owned());
    }

    if is_valid_ascii(bytes) {
        return String::from_utf8(bytes.to_vec())
            .unwrap_or_else(|_| String::from_utf8_lossy(bytes).into_owned());
    }

    if is_likely_gbk(bytes) {
        if let Some(decoded) = GBK.decode_without_bom_handling_and_without_replacement(bytes) {
            return decoded.into_owned();
        }
    }

    let (decoded, _, _) = WINDOWS_1252.decode(bytes);
    if !decoded.is_empty() {
        return decoded.into_owned();
    }

    decode_latin1(bytes).into_owned()
}

/// 解析 VTT 文本并输出 LRC 行
pub fn parse_vtt_content(decoded_content: &str) -> Result<Vec<String>, ConvertError> {
    let content: Vec<&str> = decoded_content.lines().collect();
    let mut output = Vec::new();
    let mut index = 0;

    while index < content.len() {
        let line = content[index].trim();
        if let Some(arrow_index) = line.find("-->") {
            let start = line[..arrow_index].trim();
            let lrc_time = vtt_time_to_lrc(start)
                .ok_or_else(|| ConvertError::Format(format!("无法解析时间戳: {start}")))?;

            index += 1;
            let mut text_parts = Vec::new();
            while index < content.len() && !content[index].trim().is_empty() {
                text_parts.push(clean_vtt_text(content[index].trim()));
                index += 1;
            }

            output.push(format!("{lrc_time}{}", text_parts.join(" ")));
        }

        index += 1;
    }

    Ok(output)
}

/// 转换单个文件并写回同目录 `.lrc`
pub fn convert_vtt_to_lrc(path: &Path) -> Result<PathBuf, ConvertError> {
    let bytes =
        fs::read(path).map_err(|error| ConvertError::Io(format!("文件访问失败：{error}")))?;
    let decoded_content = detect_and_decode(&bytes);
    let lrc_lines = parse_vtt_content(&decoded_content)?;

    let lrc_path = output_path(path);
    fs::write(&lrc_path, lrc_lines.join("\n"))
        .map_err(|error| ConvertError::Io(format!("文件访问失败：{error}")))?;

    Ok(lrc_path)
}

/// 并发转换文件列表
pub fn convert_files_parallel(
    file_paths: &[PathBuf],
    worker_count: usize,
) -> Result<Vec<ConvertResult>, String> {
    let vtt_files: Vec<PathBuf> = file_paths
        .iter()
        .filter(|path| is_vtt_path(path))
        .map(|path| to_absolute_path(path))
        .collect();

    if vtt_files.is_empty() {
        return Ok(Vec::new());
    }

    let pool = ThreadPoolBuilder::new()
        .num_threads(worker_count.max(1))
        .build()
        .map_err(|error| format!("无法初始化并发线程池：{error}"))?;

    let results = pool.install(|| {
        vtt_files
            .par_iter()
            .map(|path| convert_single_file(path))
            .collect::<Vec<_>>()
    });

    Ok(results)
}

fn convert_single_file(path: &Path) -> ConvertResult {
    match convert_vtt_to_lrc(path) {
        Ok(destination) => ConvertResult::success(path.to_path_buf(), destination),
        Err(error) => ConvertResult::failure(path.to_path_buf(), format!("转换失败：{error}")),
    }
}

fn output_path(source: &Path) -> PathBuf {
    let mut output = source.to_path_buf();
    output.set_extension("lrc");
    output
}

fn has_utf8_bom(bytes: &[u8]) -> bool {
    matches!(bytes, [0xEF, 0xBB, 0xBF, ..])
}

fn is_valid_utf8(bytes: &[u8]) -> bool {
    std::str::from_utf8(bytes).is_ok()
}

fn is_valid_ascii(bytes: &[u8]) -> bool {
    bytes.is_ascii()
}

fn is_likely_gbk(bytes: &[u8]) -> bool {
    bytes.windows(2).any(|window| {
        let first = window[0];
        let second = window[1];
        (0x81..=0xFE).contains(&first) && (0x40..=0xFE).contains(&second) && second != 0x7F
    })
}

fn tag_regex() -> &'static Regex {
    static TAG_REGEX: OnceLock<Regex> = OnceLock::new();
    TAG_REGEX.get_or_init(|| {
        Regex::new(r"(?i)<(/?)(b|i|c|u|ruby|rt)(?:[.\s][^>]*)?>").expect("VTT 标签正则必须有效")
    })
}

fn timestamp_regex() -> &'static Regex {
    static TIMESTAMP_REGEX: OnceLock<Regex> = OnceLock::new();
    TIMESTAMP_REGEX.get_or_init(|| {
        Regex::new(r"^(\d+):([0-5]\d):([0-5]\d)\.\d{3}$").expect("时间戳正则必须有效")
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn 清理常见_vtt_标签() {
        assert_eq!(clean_vtt_text("<b>粗体</b>"), "粗体");
        assert_eq!(clean_vtt_text("<c.class>颜色</c>"), "颜色");
        assert_eq!(
            clean_vtt_text("<ruby>注音<rt>zhuyin</rt></ruby>"),
            "注音zhuyin"
        );
        assert_eq!(clean_vtt_text("<B>大写</B>"), "大写");
    }

    #[test]
    fn 转换标准时间戳() {
        assert_eq!(
            vtt_time_to_lrc("00:00:05.000"),
            Some("[00:05.00]".to_string())
        );
        assert_eq!(
            vtt_time_to_lrc("01:30:45.678"),
            Some("[90:45.67]".to_string())
        );
        assert_eq!(vtt_time_to_lrc("00:00:05.0"), None);
    }

    #[test]
    fn 检测编码优先级() {
        assert_eq!(detect_encoding("Hello".as_bytes()), EncodingType::Utf8);
        assert_eq!(
            detect_encoding(&[0xD6, 0xD0, 0xCE, 0xC4]),
            EncodingType::Gbk
        );
        assert_eq!(detect_encoding(&[0xE9, 0xE0, 0xE8]), EncodingType::Latin1);
    }

    #[test]
    fn 解码多种输入内容() {
        let utf8_bom = [0xEF, 0xBB, 0xBF, b'H', b'i'];
        assert_eq!(detect_and_decode(&utf8_bom), "Hi");
        assert_eq!(detect_and_decode(&[0xD6, 0xD0, 0xCE, 0xC4]), "中文");
        assert_eq!(detect_and_decode(&[0x80]), "€");
        assert_eq!(detect_and_decode(&[0xE9, 0xE0, 0xE8]), "éàè");
    }

    #[test]
    fn 解析无效时间戳时报错() {
        let content = "WEBVTT\n\ninvalid --> 00:00:01.000\n字幕";
        let error = parse_vtt_content(content).expect_err("应当返回格式错误");
        assert_eq!(
            error,
            ConvertError::Format("无法解析时间戳: invalid".to_string())
        );
    }

    #[test]
    fn 转换文件并输出_lrc() {
        let dir = tempdir().expect("临时目录应当创建成功");
        let source = dir.path().join("song.vtt");
        fs::write(
            &source,
            "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n第一行\n第二行\n",
        )
        .expect("测试文件应当写入成功");

        let destination = convert_vtt_to_lrc(&source).expect("转换应当成功");
        let output = fs::read_to_string(destination).expect("结果文件应当可读");

        assert!(output.contains("[00:01.00]第一行 第二行"));
    }

    #[test]
    fn 并发转换时忽略非_vtt_文件() {
        let dir = tempdir().expect("临时目录应当创建成功");
        let source = dir.path().join("song.vtt");
        let ignored = dir.path().join("note.txt");
        fs::write(&source, "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n第一行\n")
            .expect("测试文件应当写入成功");
        fs::write(&ignored, "ignore").expect("文本文件应当写入成功");

        let results =
            convert_files_parallel(&[source.clone(), ignored], 4).expect("转换结果应当返回");

        assert_eq!(results.len(), 1);
        assert!(results[0].is_success());
        assert_eq!(results[0].source, to_absolute_path(&source));
    }
}
