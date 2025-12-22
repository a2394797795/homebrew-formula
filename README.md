# Homebrew Tap: zotero-pdf2zh

这是一个用于安装/运行 [`guaguastandup/zotero-pdf2zh`](https://github.com/guaguastandup/zotero-pdf2zh) 本地服务端的 Homebrew tap。

本仓库的目标：

- **上游代码自动跟进**：每天自动检查 `guaguastandup/zotero-pdf2zh` 的最新 Release，自动更新 Formula（`url`/`sha256`），并自动创建 PR + 启用 auto-merge。
- **依赖升级可控**：Python 依赖（例如 `pdf2zh_next`）不在每次服务启动时强制联网升级；而是在 **brew 升级后** 或你 **主动执行更新命令** 时才升级，并在需要时重启服务。

---

## 安装

```bash
brew tap a2394797795/homebrew-formula
brew install zotero-pdf2zh
```

---

## 运行（作为服务）

```bash
brew services start zotero-pdf2zh
```

默认端口在 formula 的 `service do ... run [...]` 中设置（当前为 `47700`）。

查看状态/日志：

```bash
brew services list
tail -n 200 "$(brew --prefix)/var/log/zotero-pdf2zh.log"
```

---

## 配置与数据目录

该服务会把可写数据放在 Homebrew 的 `var` 下：

- 数据根目录：`$(brew --prefix)/var/zotero-pdf2zh`
- 翻译输出：`$(brew --prefix)/var/zotero-pdf2zh/translated`
- 可写配置目录：`$(brew --prefix)/var/zotero-pdf2zh/config`
- Python venv：`$(brew --prefix)/var/zotero-pdf2zh/venv`

启动时会把可写目录软链接到安装目录结构中，以保持上游目录布局兼容。

---

## 更新策略（使用者视角）

### 1) 上游 zotero-pdf2zh 代码更新（自动）

本仓库通过 GitHub Actions 定时检查上游 Release，并更新 Formula。你本机只需要：

```bash
brew update
brew upgrade zotero-pdf2zh
brew services restart zotero-pdf2zh
```

### 2) Python 依赖更新（例如 pdf2zh_next）

本仓库提供两种方式更新依赖：

**A. brew 升级后自动触发一次依赖刷新**

- 每次 `brew install/reinstall/upgrade zotero-pdf2zh` 后，都会写入一个 marker 文件：
  - `$(brew --prefix)/var/zotero-pdf2zh/needs-deps-update`
- 下次服务启动时如果检测到 marker，会执行一次依赖更新，然后清除 marker（失败不会阻止服务启动）。

**B. 你手动触发依赖更新（推荐用于“我现在就要升级”）**

```bash
zotero-pdf2zh-update
```

- 如果 `pdf2zh_next` 版本发生变化：会自动重启服务
- 如果没有变化：不会重启
- 如果更新后 `import pdf2zh_next` 失败：会报错并拒绝重启（避免把服务重启到坏环境）

---

## 维护者指南（本仓库维护者视角）

### 自动 bump workflow

- 工作流文件：`.github/workflows/update-zotero-pdf2zh.yml`
- 行为：
  - 读取 Formula 当前版本（tag）和 sha256
  - 查询上游最新 Release tag
  - 若 tag 更新，或 sha256 为占位值（全 0）则触发更新
  - 使用 `gh release download` 下载 Release 资产并计算 sha256
  - 只修改 `Formula/zotero-pdf2zh.rb` 并创建 PR（不会提交下载的 zip）
  - 自动启用 PR 的 squash auto-merge

### 仓库设置要求

在 GitHub 仓库设置中需要：

- `Settings → Actions → General`
  - **Workflow permissions**：Read and write
  - 允许 Actions 创建/批准 PR
- `Settings → General → Pull Requests`
  - 允许 auto-merge（可选，但推荐）
  - 推荐只启用 squash merge

---

## 常见问题

### brew 安装时报 sha256 不匹配

这说明上游 Release 的 zip 内容变化或 formula 未及时更新。处理方式：

- 在 GitHub Actions 页面手动触发一次 `Update zotero-pdf2zh` workflow（或等待定时任务）
- 确认对应 PR 合并后再 `brew upgrade zotero-pdf2zh`
