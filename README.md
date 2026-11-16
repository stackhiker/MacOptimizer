<p align="center">
  <img src="generated_icon.png" width="128" height="128" alt="MacOptimizer Logo">
</p>

<h1 align="center">MacOptimizer</h1>

<p align="center">
  <strong>🚀 A Powerful macOS System Optimization and App Management Tool</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013.0+-blue.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-4.0-purple.svg" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/version-5.0-brightgreen.svg" alt="Version">
  <img src="https://img.shields.io/badge/i18n-6%20languages-cyan.svg" alt="i18n">
</p>

---

## ✨ Features

MacOptimizer is a system optimization tool designed specifically for macOS, featuring a modern SwiftUI interface with the following core modules:

特别推出AI影视与设计平台，专注于AI短剧，AI设计智能体平台。体验地址：https://zaomeng.art

### 🌐 Multi-Language Support (New!)
- **Chinese & English** - Switch between languages with one click
- **Persistent Settings** - Language preference is saved automatically
- **Full Coverage** - All UI elements support localization

### 🖥️ Console (System Monitor)
- **CPU Usage** - Real-time CPU usage monitoring
- **Memory Status** - Display used/available memory
- **Disk Space** - Visual disk usage percentage
- **Process Management** - View and manage running apps and background processes
- **One-Click Stop** - Quickly terminate unwanted processes

### 📦 App Uninstaller
- **Smart Scanning** - Automatically detect installed applications
- **Residual File Detection** - Find all associated residual files:
  - Preferences
  - Application Support
  - Caches
  - Logs
  - Saved State
  - Containers
  - Launch Agents
  - Crash Reports
- **Complete Uninstall** - Remove app and all related files with one click
- **Selective Deletion** - Choose to delete only residuals or include the app
- **Move to Trash** - Safe deletion with recovery option

### 🧹 Junk Cleaner
- **System Cache** - Clean macOS system cache
- **App Cache** - Clean cache files from various applications
- **Browser Cache** - Support Safari, Chrome, Firefox, and more
- **Log Files** - Clean system and app logs
- **Categorized Display** - Group by type, support selective cleaning

### ⚡ System Optimizer
- **Startup Items** - View and disable startup items
- **Memory Release** - One-click system memory cleanup
- **System Acceleration** - Optimize system performance

### 🔍 Large File Finder
- **Smart Scanning** - Quickly locate space-consuming files
- **Multi-Directory Scan** - Scan all files in home directory
- **Visual Display** - Clear file size and location display
- **Quick Cleanup** - Direct delete or move to trash

### 🗑️ Trash Manager
- **View Contents** - Browse all files in trash
- **Space Statistics** - Show trash space usage
- **One-Click Empty** - Quickly empty trash to free space

### ✨ Deep Clean
- **Orphaned File Scan** - Scan residual files from uninstalled apps
- **Smart Recognition** - Auto-identify files not belonging to installed apps
- **System Protection** - Auto-exclude Apple system files to prevent accidental deletion
- **Categorized Display** - Group by type: App Support, Cache, Preferences, Containers, Logs
- **Selective Cleanup** - Support select all/none, freely choose items to clean
- **Safe Deletion** - Files move to trash for recovery

### 📁 File Explorer
- **Disk Browsing** - Browse entire Mac disk directory structure
- **Quick Access** - Home, Desktop, Documents, Downloads, Applications, Disk Root
- **Navigation** - Forward/Back/Parent + Breadcrumb path bar
- **Path Input** - Manual path input for quick navigation (supports `~`)
- **File Operations** - New folder, new file, rename, delete
- **Hidden Files** - Toggle show/hide system hidden files
- **Terminal Integration** - One-click open current directory in Terminal
- **Context Menu** - Open, Show in Finder, Rename, Delete

---

## 📸 Screenshots
<img width="2180" height="1344" alt="image" src="https://github.com/user-attachments/assets/c25c15ae-079e-4054-b3f6-3593e40182f5" />

<img width="2180" height="1344" alt="image" src="https://github.com/user-attachments/assets/482c74a8-be5f-4569-87a3-36291da5e615" />

<img width="2180" height="1344" alt="image" src="https://github.com/user-attachments/assets/faf31feb-840f-404f-a8a8-3a8c55f0ca45" />

<img width="2180" height="1344" alt="image" src="https://github.com/user-attachments/assets/5da494f5-e26d-481b-8226-863e97489f4f" />


---

## 🛠️ Installation & Build

### System Requirements
- **macOS 13.0 (Ventura)** or later
- **Apple Silicon (M1/M2/M3/M4)** or Intel
- **Command Line Tools** and **Python 3** (Full Xcode not required)


### Download DMG

Download the latest release from [GitHub Releases](https://github.com/ddlmanus/MacOptimizer/releases):
- **Apple Silicon (M1/M2/M3/M4)**: `MacOptimizer_vX.X.X_AppleSilicon.dmg`
- **Intel**: `MacOptimizer_vX.X.X_Intel.dmg`

### Build from Source

```bash
git clone https://github.com/stackhiker/MacOptimizer.git
cd MacOptimizer

# Build and verify the Apple Silicon App and DMG.
./build.sh
open build/Mac优化大师.app

# Build, verify, install to /Applications, and launch.
./build.sh --install

# Intel build, or package both architectures.
./build.sh --arch x86_64
./release_package.sh
```

The scripts can be called from any working directory. Single-architecture output stays in `build/`; dual-architecture output stays in `build_release/`. Use `--install-dir "$HOME/Applications"` with `--install` for a user-local installation. For a dual-architecture package, installation selects the current Mac's architecture; a single-architecture installation must match this Mac.

Each run uses a private temporary directory and compiler module cache, removed on normal success or failure. A shared packaging lock rejects overlapping builds. Existing successful outputs are replaced only after compilation, signature, architecture, and DMG checks pass; installation additionally verifies the installed bundle and launch, with rollback on failure.

Successful runs retain the current App/DMG set. Successful installation retains at most one rollback archive at `backups/previous-install.zip` in the output directory. Only recognized historical packages or artifacts recorded by the build manifest are retired. Historical rollback ZIPs are removed only when a verified replacement archive exists. Source files, unknown files, shared `.build` validation data, and unrelated temporary directories are preserved. If recovery itself fails, the script reports and retains a recovery directory instead of deleting the previous outputs.

Run the build-script regression checks with:

```bash
python3 -B -m unittest discover -s Tests/BuildScripts -v
```

---

## 📁 Project Structure

```
MacOptimizer/
├── AppUninstaller/              # Source code
│   ├── AppUninstallerApp.swift  # App entry
│   ├── ContentView.swift        # Main view
│   ├── NavigationSidebar.swift  # Sidebar navigation
│   ├── LocalizationManager.swift # i18n manager (New!)
│   ├── Models.swift             # Data models
│   ├── Styles.swift             # Global styles
│   │
│   ├── MonitorView.swift        # Console view
│   ├── SystemMonitorService.swift
│   ├── ProcessService.swift
│   │
│   ├── AppScanner.swift         # App scanner
│   ├── AppDetailView.swift      # App detail view
│   ├── ResidualFileScanner.swift
│   ├── FileRemover.swift
│   │
│   ├── JunkCleaner.swift        # Junk cleaner
│   ├── JunkCleanerView.swift
│   │
│   ├── SystemOptimizer.swift    # System optimizer
│   ├── OptimizerView.swift
│   │
│   ├── LargeFileScanner.swift   # Large file scanner
│   ├── LargeFileView.swift
│   │
│   ├── TrashView.swift          # Trash view
│   ├── DiskSpaceManager.swift
│   ├── DiskUsageView.swift
│   │
│   ├── DeepCleanScanner.swift   # Deep clean
│   ├── DeepCleanView.swift
│   │
│   ├── FileExplorerService.swift # File explorer
│   ├── FileExplorerView.swift
│   │
│   ├── Info.plist
│   └── AppIcon.icns
│
├── build.sh                     # Build script
├── release_package.sh           # Release packaging
└── README.md
```

---

## 🔧 Tech Stack

- **Language**: Swift 5.9
- **UI Framework**: SwiftUI 4.0
- **Minimum Support**: macOS 13.0 (Ventura)
- **Architecture**: MVVM
- **Build Tool**: Swift Compiler (swiftc)

---

## 🚀 Roadmap

- [x] Multi-language support (English/中文)
- [ ] Scheduled cleanup tasks
- [x] Menu bar widget
- [x] App update detection
- [ ] Duplicate file finder
- [x] Privacy protection (browsing history cleanup)

---

## 🤝 Contributing

Contributions are welcome! Submit a Pull Request or create an Issue.

1. Fork this repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Create Pull Request

---

## 📄 License

This project is open source under the [MIT License](LICENSE).

---

## ⚠️ Disclaimer

- Back up important data before use
- Deleting system files may cause apps to malfunction
- Recommend using "Move to Trash" first, then empty after confirming
- This tool is for learning and personal use only

---

<p align="center">
  Made with ❤️ for macOS
</p>

---

# 中文说明

## ✨ 功能特性

Mac优化大师是一款专为 macOS 设计的系统优化工具，采用现代化的 SwiftUI 界面，提供以下核心功能模块：

### 🌐 多语言支持（新功能！）
- **中英双语** - 一键切换界面语言
- **设置持久化** - 语言偏好自动保存
- **全覆盖** - 所有界面元素均支持本地化

### 🖥️ 控制台（系统监控）
- **CPU 占用率** - 实时监控 CPU 使用情况
- **内存状态** - 显示已用/可用内存
- **磁盘空间** - 可视化磁盘使用占比
- **进程管理** - 查看并管理运行中的应用和后台进程
- **一键停止进程** - 快速终止不需要的进程

### 📦 应用卸载
- **智能扫描** - 自动检测已安装的应用程序
- **残留文件检测** - 发现应用关联的所有残留文件
  - 偏好设置 (Preferences)
  - 应用支持 (Application Support)
  - 缓存文件 (Caches)
  - 日志文件 (Logs)
  - 保存状态 (Saved State)
  - 容器 (Containers)
  - 启动代理 (Launch Agents)
  - 崩溃报告 (Crash Reports)
- **完全卸载** - 一键删除应用及所有相关文件
- **选择性删除** - 可选择仅删除残留文件或连同应用一起删除
- **移至废纸篓** - 支持安全删除，可从废纸篓恢复

### 🧹 垃圾清理
- **系统缓存** - 清理 macOS 系统缓存
- **应用缓存** - 清理各应用产生的缓存文件
- **浏览器缓存** - 支持 Safari、Chrome、Firefox 等主流浏览器
- **日志文件** - 清理系统和应用日志
- **分类展示** - 按类型分组显示，支持选择性清理

### ⚡ 系统优化
- **启动项管理** - 查看和禁用开机启动项
- **内存释放** - 一键清理系统内存
- **系统加速** - 优化系统性能

### 🔍 大文件查找
- **智能扫描** - 快速定位占用大量空间的文件
- **多目录扫描** - 扫描主目录下的所有文件
- **可视化展示** - 清晰展示文件大小和位置
- **快速清理** - 支持直接删除或移至废纸篓

### 🗑️ 废纸篓管理
- **查看内容** - 浏览废纸篓中的所有文件
- **空间统计** - 显示废纸篓占用空间
- **一键清空** - 快速清空废纸篓释放空间

### ✨ 深度清理
- **孤立文件扫描** - 扫描已卸载应用的残留文件
- **智能识别** - 自动识别不属于任何已安装应用的文件
- **系统保护** - 自动排除 Apple 系统文件，防止误删
- **分类展示** - 按类型分组：应用支持、缓存、偏好设置、容器、日志等
- **选择性清理** - 支持全选/反选，自由选择要清理的项目
- **安全删除** - 文件移至废纸篓，可恢复

### 📁 文件管理
- **磁盘浏览** - 浏览整个 Mac 磁盘目录结构
- **快捷访问** - 主目录、桌面、文稿、下载、应用程序、磁盘根目录
- **导航功能** - 前进/后退/上级目录 + 面包屑路径栏
- **路径输入** - 支持手动输入路径快速跳转（支持 `~` 主目录）
- **文件操作** - 新建文件夹、新建文件、重命名、删除
- **显示隐藏文件** - 可切换显示/隐藏系统隐藏文件
- **终端集成** - 一键在系统终端中打开当前目录
- **右键菜单** - 打开、在 Finder 中显示、重命名、删除

---

## 🛠️ 安装与构建

### 系统要求
- **macOS 13.0 (Ventura)** 或更高版本
- **Apple Silicon (M1/M2/M3/M4)** 或 Intel 芯片（需修改编译参数）
- **Command Line Tools**（无需安装完整 Xcode）

### 通过 Homebrew 安装（推荐）

```bash
# 使用 Homebrew Cask 安装
brew tap ddlmanus/macoptimizer
brew install --cask macoptimizer
```

或者从本地 cask 文件安装：

```bash
brew install --cask ./homebrew/macoptimizer.rb
```

### 下载 DMG

从 [GitHub Releases](https://github.com/ddlmanus/MacOptimizer/releases) 下载最新版本：
- **Apple Silicon (M1/M2/M3/M4)**: `MacOptimizer_vX.X.X_AppleSilicon.dmg`
- **Intel**: `MacOptimizer_vX.X.X_Intel.dmg`

### 从源码编译

```bash
git clone https://github.com/stackhiker/MacOptimizer.git
cd MacOptimizer

# 构建并校验 Apple Silicon App 和 DMG
./build.sh
open build/Mac优化大师.app

# 构建、校验、覆盖安装到 /Applications 并启动
./build.sh --install

# 构建 Intel 版本，或打包双架构版本
./build.sh --arch x86_64
./release_package.sh
```

脚本支持从任意工作目录调用。单架构产物位于 `build/`，双架构产物位于 `build_release/`。使用 `--install --install-dir "$HOME/Applications"` 可安装到个人应用目录；双架构安装时选择本机对应的架构；单架构安装必须与本机匹配。

每轮使用独立临时目录和编译模块缓存，正常成功或失败退出时均清理本轮临时文件；同一仓库的并行构建会被拒绝。编译、签名、架构和 DMG 校验全部通过后才更新成品；安装模式还会校验已安装应用并确认启动，失败时恢复旧版本。

成功后只保留当前 App/DMG 产物。安装成功后最多保留一份回滚包，位于输出目录的 `backups/previous-install.zip`。自动清理仅处理构建清单记录的旧产物及可核验的历史安装包；旧回滚 ZIP 只有在存在有效替代回滚包时才清理。源码、未知文件、共享 `.build` 验证数据和其他临时目录会保留。若恢复过程本身受阻，会保留恢复目录并提示其路径。

构建脚本的回归检查：

```bash
python3 -B -m unittest discover -s Tests/BuildScripts -v
```

如果觉得对你有帮助，可以点个 star 哦  开发不易，你的支持就是我最大的动力

---

问题收集和建议
https://docs.qq.com/sheet/DY0xIdGZxckVvQUFk?no_promotion=1&is_blank_or_template=blank&tab=s3z6cr

## ⚠️ 免责声明

- 请在使用前备份重要数据
- 删除系统文件可能导致应用无法正常工作
- 建议先使用"移至废纸篓"功能，确认无误后再清空
- 本工具仅供学习和个人使用

---

<p align="center">
  Made with ❤️ for macOS
</p>
