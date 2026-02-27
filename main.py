import os
import sys
from datetime import datetime
from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QTextEdit, QFileDialog,
    QMessageBox, QFrame
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont


# ─── 转换逻辑 ──────────────────────────────────────────────────────────────────

def vtt_time_to_lrc(t):
    h, m, s = t.split(":")
    s, ms = s.split(".")
    total_ms = (int(h) * 3600 + int(m) * 60 + int(s)) * 1000 + int(ms)
    return f"[{total_ms // 60000:02d}:{(total_ms % 60000) // 1000:02d}.{(total_ms % 1000) // 10:02d}]"


def convert_vtt_to_lrc(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    out = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if "-->" in line:
            start = line.split("-->")[0].strip()
            lrc_time = vtt_time_to_lrc(start)
            i += 1
            text = ""
            while i < len(lines) and lines[i].strip() != "":
                text += lines[i].strip() + " "
                i += 1
            out.append(lrc_time + text.strip())
        i += 1

    base_name = path.replace(".vtt", "")
    if base_name.count(".") > 0:
        parts = base_name.rsplit(".", 1)
        base_name = parts[0]

    lrc_path = base_name + ".lrc"
    with open(lrc_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    return lrc_path


def convert_files(filepaths):
    results = []
    for path in filepaths:
        if path.endswith(".vtt") and os.path.isfile(path):
            lrc_path = convert_vtt_to_lrc(path)
            results.append((path, lrc_path))
    return results


def scan_directory_for_vtt(directory):
    """递归扫描目录及其子目录下的所有 VTT 文件"""
    vtt_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith(".vtt"):
                vtt_files.append(os.path.join(root, file))
    return vtt_files


# ─── 全局样式表 ─────────────────────────────────────────────────────────────────

STYLESHEET = """
/* ── 窗口主体 ── */
QWidget#mainWindow {
    background: #1b1b30;
}

/* ── 标题 ── */
QLabel#titleLabel {
    font-size: 26px;
    font-weight: 800;
    color: #e0e0ff;
    letter-spacing: 2px;
}

QLabel#subtitleLabel {
    font-size: 13px;
    color: #8888bb;
    font-weight: 400;
}

/* ── 通用按钮基础 ── */
QPushButton {
    border: none;
    border-radius: 10px;
    padding: 12px 24px;
    font-size: 14px;
    font-weight: 600;
    color: #ffffff;
    min-height: 20px;
}

/* ── 选择文件按钮 ── */
QPushButton#btnSelectFiles {
    background: #667eea;
}
QPushButton#btnSelectFiles:hover {
    background: #7b93ff;
}
QPushButton#btnSelectFiles:pressed {
    background: #5569d0;
}

/* ── 选择目录按钮 ── */
QPushButton#btnSelectDir {
    background: #43e97b;
    color: #0a3d2e;
}
QPushButton#btnSelectDir:hover {
    background: #5cff96;
}
QPushButton#btnSelectDir:pressed {
    background: #36cc6a;
}

/* ── 转换按钮 ── */
QPushButton#btnConvert {
    background: #f5576c;
}
QPushButton#btnConvert:hover {
    background: #ff6b80;
}
QPushButton#btnConvert:pressed {
    background: #d94558;
}
QPushButton#btnConvert:disabled {
    background: #3a3a5c;
    color: #666688;
}

/* ── 清除按钮 ── */
QPushButton#btnClear {
    background: transparent;
    border: 1px solid #555577;
    color: #9999bb;
    padding: 8px 16px;
    font-size: 12px;
    border-radius: 8px;
}
QPushButton#btnClear:hover {
    border-color: #ff6a88;
    color: #ff6a88;
}

/* ── 状态标签 ── */
QLabel#statusLabel {
    font-size: 13px;
    font-weight: 500;
    color: #aaaacc;
    padding: 6px 12px;
    background: rgba(255, 255, 255, 0.04);
    border-radius: 8px;
    border: 1px solid rgba(255, 255, 255, 0.06);
}

/* ── 文件计数标签 ── */
QLabel#fileCountLabel {
    font-size: 12px;
    color: #8888aa;
    padding: 4px 0px;
}

/* ── 日志标题标签 ── */
QLabel#logTitleLabel {
    font-size: 13px;
    font-weight: 600;
    color: #bbbbdd;
    padding: 4px 0px;
}

/* ── 日志文本框 ── */
QTextEdit#logArea {
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid rgba(255, 255, 255, 0.07);
    border-radius: 10px;
    padding: 12px;
    font-family: 'SF Mono', 'JetBrains Mono', 'Fira Code', 'Menlo', monospace;
    font-size: 12px;
    color: #ccccdd;
    selection-background-color: #667eea;
}

/* ── 滚动条 ── */
QScrollBar:vertical {
    background: transparent;
    width: 8px;
    margin: 4px 2px;
    border-radius: 4px;
}
QScrollBar::handle:vertical {
    background: rgba(255, 255, 255, 0.15);
    border-radius: 4px;
    min-height: 30px;
}
QScrollBar::handle:vertical:hover {
    background: rgba(255, 255, 255, 0.25);
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0px;
}
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
    background: none;
}

/* ── 分隔线 ── */
QFrame#separator {
    background: rgba(255, 255, 255, 0.12);
    max-height: 1px;
    min-height: 1px;
}

/* ── 消息框 ── */
QMessageBox {
    background: #24243e;
}
QMessageBox QLabel {
    color: #ccccdd;
    font-size: 13px;
}
QMessageBox QPushButton {
    background: #667eea;
    min-width: 80px;
    padding: 8px 20px;
}
"""


# ─── 应用主窗口 ─────────────────────────────────────────────────────────────────

class VTTConverterApp(QWidget):
    def __init__(self):
        super().__init__()
        self.selected_files = []
        self.selected_directory = ""
        self.setObjectName("mainWindow")
        self.setup_ui()

    def setup_ui(self):
        self.setWindowTitle("VTT → LRC 转换器")
        self.setMinimumSize(720, 520)
        self.resize(750, 560)

        main_layout = QVBoxLayout()
        main_layout.setSpacing(12)
        main_layout.setContentsMargins(28, 24, 28, 20)

        # ── 头部区域 ────────────────────────────────────────
        header_layout = QVBoxLayout()
        header_layout.setSpacing(4)

        title = QLabel("✦  VTT → LRC 转换器")
        title.setObjectName("titleLabel")
        title.setAlignment(Qt.AlignmentFlag.AlignLeft)

        subtitle = QLabel("将 WebVTT 字幕文件批量转换为 LRC 歌词格式")
        subtitle.setObjectName("subtitleLabel")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignLeft)

        header_layout.addWidget(title)
        header_layout.addWidget(subtitle)
        main_layout.addLayout(header_layout)

        # ── 分隔线 ──────────────────────────────────────────
        sep1 = QFrame()
        sep1.setObjectName("separator")
        sep1.setFrameShape(QFrame.Shape.HLine)
        main_layout.addWidget(sep1)

        # ── 按钮行 ──────────────────────────────────────────
        button_layout = QHBoxLayout()
        button_layout.setSpacing(12)

        self.btn_select = QPushButton("📄  选择文件")
        self.btn_select.setObjectName("btnSelectFiles")
        self.btn_select.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_select.setMinimumWidth(160)

        self.btn_select_dir = QPushButton("📂  选择目录")
        self.btn_select_dir.setObjectName("btnSelectDir")
        self.btn_select_dir.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_select_dir.setMinimumWidth(160)

        self.btn_convert = QPushButton("⚡  开始转换")
        self.btn_convert.setObjectName("btnConvert")
        self.btn_convert.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_convert.setMinimumWidth(160)
        self.btn_convert.setEnabled(False)

        button_layout.addWidget(self.btn_select)
        button_layout.addWidget(self.btn_select_dir)
        button_layout.addWidget(self.btn_convert)
        button_layout.addStretch()

        main_layout.addLayout(button_layout)

        # ── 状态行 ──────────────────────────────────────────
        status_row = QHBoxLayout()
        status_row.setSpacing(8)

        self.lbl_status = QLabel("⏳  未选择文件或目录")
        self.lbl_status.setObjectName("statusLabel")

        self.btn_clear = QPushButton("✕ 清除")
        self.btn_clear.setObjectName("btnClear")
        self.btn_clear.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_clear.setVisible(False)

        status_row.addWidget(self.lbl_status, 1)
        status_row.addWidget(self.btn_clear)

        main_layout.addLayout(status_row)

        # ── 日志区域 ────────────────────────────────────────
        log_title_row = QHBoxLayout()
        log_title = QLabel("📋  操作日志")
        log_title.setObjectName("logTitleLabel")
        self.lbl_file_count = QLabel("")
        self.lbl_file_count.setObjectName("fileCountLabel")
        self.lbl_file_count.setAlignment(Qt.AlignmentFlag.AlignRight)
        log_title_row.addWidget(log_title)
        log_title_row.addWidget(self.lbl_file_count)
        main_layout.addLayout(log_title_row)

        self.text_log = QTextEdit()
        self.text_log.setObjectName("logArea")
        self.text_log.setReadOnly(True)
        self.text_log.setMinimumHeight(180)
        self.text_log.setPlaceholderText("操作日志将在此处显示…")

        main_layout.addWidget(self.text_log, 1)  # stretch=1 让日志区占满空间

        self.setLayout(main_layout)

        # ── 信号连接 ────────────────────────────────────────
        self.btn_select.clicked.connect(self.on_select_files)
        self.btn_select_dir.clicked.connect(self.on_select_directory)
        self.btn_convert.clicked.connect(self.on_convert_selected)
        self.btn_clear.clicked.connect(self.on_clear_selection)

    # ── 辅助方法 ────────────────────────────────────────────────────────────

    def _timestamp(self):
        return datetime.now().strftime("%H:%M:%S")

    def log(self, msg, color=None):
        ts = self._timestamp()
        if color:
            html = f'<span style="color:#555577">[{ts}]</span> <span style="color:{color}">{msg}</span>'
        else:
            html = f'<span style="color:#555577">[{ts}]</span> <span style="color:#ccccdd">{msg}</span>'
        self.text_log.append(html)
        scrollbar = self.text_log.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def _update_file_count(self, count):
        if count > 0:
            self.lbl_file_count.setText(f"共 {count} 个文件")
        else:
            self.lbl_file_count.setText("")

    # ── 交互逻辑 ────────────────────────────────────────────────────────────

    def on_select_files(self):
        files, _ = QFileDialog.getOpenFileNames(
            self,
            "选择 VTT 文件",
            "",
            "VTT 文件 (*.vtt);;所有文件 (*.*)"
        )
        if files:
            self.selected_files = files
            self.selected_directory = ""
            self.lbl_status.setText(f"📄  已选择 {len(files)} 个文件")
            self.btn_convert.setEnabled(True)
            self.btn_clear.setVisible(True)
            self._update_file_count(len(files))
            self.log("选择了文件：", "#667eea")
            for f in files:
                self.log(f"   {os.path.basename(f)}", "#9999cc")
        else:
            self.selected_files = []
            self._check_empty()

    def on_select_directory(self):
        directory = QFileDialog.getExistingDirectory(
            self,
            "选择包含 VTT 文件的目录",
            "",
            QFileDialog.Option.ShowDirsOnly
        )
        if directory:
            self.selected_directory = directory
            self.selected_files = []
            vtt_files = scan_directory_for_vtt(directory)
            count = len(vtt_files)
            self.lbl_status.setText(f"📂  {os.path.basename(directory)}/  — 发现 {count} 个 VTT 文件")
            self.btn_convert.setEnabled(count > 0)
            self.btn_clear.setVisible(True)
            self._update_file_count(count)
            self.log(f"扫描目录：{directory}", "#43e97b")
            for f in vtt_files:
                self.log(f"   {os.path.relpath(f, directory)}", "#9999cc")
        else:
            self.selected_directory = ""
            self._check_empty()

    def on_clear_selection(self):
        self.selected_files = []
        self.selected_directory = ""
        self.lbl_status.setText("⏳  未选择文件或目录")
        self.btn_convert.setEnabled(False)
        self.btn_clear.setVisible(False)
        self._update_file_count(0)
        self.log("已清除选择", "#ff6a88")

    def _check_empty(self):
        if not self.selected_files and not self.selected_directory:
            self.lbl_status.setText("⏳  未选择文件或目录")
            self.btn_convert.setEnabled(False)
            self.btn_clear.setVisible(False)
            self._update_file_count(0)

    def on_convert_selected(self):
        files_to_convert = []

        if self.selected_files:
            files_to_convert = self.selected_files
            self.log("开始转换所选文件…", "#ffcc00")
        elif self.selected_directory:
            files_to_convert = scan_directory_for_vtt(self.selected_directory)
            self.log(f"开始转换目录中的文件…", "#ffcc00")
        else:
            QMessageBox.warning(self, "提示", "请先选择要转换的 .vtt 文件或包含 VTT 文件的目录。")
            return

        if not files_to_convert:
            self.log("未找到可转换的 VTT 文件。", "#ff6a88")
            QMessageBox.information(self, "提示", "没有找到可转换的 VTT 文件。")
            return

        results = convert_files(files_to_convert)

        if results:
            for src, dst in results:
                src_name = os.path.basename(src)
                dst_name = os.path.basename(dst)
                self.log(f"✔ {src_name}  →  {dst_name}", "#43e97b")
            self.log(f"全部完成！共转换 {len(results)} 个文件 🎉", "#43e97b")
            QMessageBox.information(self, "完成", f"✅ 已成功转换 {len(results)} 个文件。")
        else:
            self.log("没有成功转换的文件。", "#ff6a88")
            QMessageBox.information(self, "提示", "没有成功转换的文件。")


# ─── 启动入口 ──────────────────────────────────────────────────────────────────

def run_gui():
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLESHEET)

    # 设置全局字体
    font = QFont("SF Pro Display", 13)
    font.setStyleStrategy(QFont.StyleStrategy.PreferAntialias)
    app.setFont(font)

    window = VTTConverterApp()
    # 居中显示
    screen = app.primaryScreen()
    if screen:
        center = screen.availableGeometry().center()
        geo = window.frameGeometry()
        geo.moveCenter(center)
        window.move(geo.topLeft())

    window.show()
    sys.exit(app.exec())


def main():
    args = sys.argv[1:]
    if args:
        for path in args:
            if os.path.isfile(path) and path.endswith(".vtt"):
                lrc_path = convert_vtt_to_lrc(path)
                print("Converted:", lrc_path)
        if not any(a.endswith(".vtt") and os.path.isfile(a) for a in args):
            for filename in os.listdir("."):
                if filename.endswith(".vtt"):
                    lrc_path = convert_vtt_to_lrc(filename)
                    print("Converted:", lrc_path)
    else:
        run_gui()


if __name__ == "__main__":
    main()