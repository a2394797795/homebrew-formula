# Homebrew Tap: zotero-pdf2zh

这是一个 Homebrew tap，用于把上游项目 [`guaguastandup/zotero-pdf2zh`](https://github.com/guaguastandup/zotero-pdf2zh) 的 **server.zip** 以 “可管理的本地服务” 形式安装到 macOS（Homebrew）。

设计原则（本仓库的边界）：

- **不修改上游源码**：server.zip 直接来自上游 Release，本 tap 只做「启动包装 + 目录布局适配」。
- **配置/数据持久化**：任何可写内容都放到 `$(brew --prefix)/var/zotero-pdf2zh`，避免写入 Cellar（升级/重装会变）。
- **启动尽量离线/可预测**：默认启动不强制联网升级依赖；依赖升级通过显式命令触发，并带健康检查/回滚。
- **上游版本自动跟进**：GitHub Actions 每天检查上游 Release，自动更新 Formula 的 `url`/`sha256` 并提 PR。

---

## 安装

```bash
brew tap a2394797795/homebrew-formula
brew install zotero-pdf2zh
```

---

## 运行与管理（brew services）

启动/停止/重启：

```bash
brew services start zotero-pdf2zh
brew services stop zotero-pdf2zh
brew services restart zotero-pdf2zh
```

查看状态与日志：

```bash
brew services list
tail -n 200 "$(brew --prefix)/var/log/zotero-pdf2zh.log"
```

不作为服务时，也可以直接前台运行：

```bash
zotero-pdf2zh --port 47700 --check_update false
```

---

## 安装后文件在哪里？

Homebrew 的三个关键位置：

- **可执行文件（命令）**：`$(brew --prefix)/bin`
  - `zotero-pdf2zh`：启动服务（包装脚本）
  - `zotero-pdf2zh-update`：升级依赖（见下文）
- **程序本体（只读）**：`$(brew --prefix)/Cellar/zotero-pdf2zh/<version>/libexec`
- **可写数据（持久化）**：`$(brew --prefix)/var/zotero-pdf2zh`
  - `config/`：配置（供 Zotero 插件读写）
  - `translated/`：输出目录
  - `venv/`：Python 虚拟环境

本 tap 会把上游期望的目录结构（`root_path/config`、`root_path/translated`）用软链接指向 `var`，这样：

- `brew upgrade/reinstall` 不会覆盖你的配置/输出
- 上游代码仍然按原路径工作

---

## 配置应该在哪里改？会不会被覆盖？

推荐方式：**在 Zotero 的 pdf2zh 插件里配置**（这才是普通用户最友好的入口）。插件会通过本地服务接口写入配置文件。

配置文件实际存储在：

- `$(brew --prefix)/var/zotero-pdf2zh/config/config.json`
- `$(brew --prefix)/var/zotero-pdf2zh/config/config.toml`
- `$(brew --prefix)/var/zotero-pdf2zh/config/venv.json`

### 重要：禁止在可写配置目录里保留 `*.example`

上游的行为是：只要 `config/` 里存在 `config.toml.example` 这种文件，它就可能在启动时“用 example 覆盖真实配置”，从而导致 API key 丢失、引擎回退等问题。

本 tap 会在 `post_install` 阶段自动清理 `$(brew --prefix)/var/zotero-pdf2zh/config/*.example` 并按需生成默认配置；如果你以前安装过旧版本导致遗留 `.example`，可以手动检查：

```bash
ls -1 "$(brew --prefix)/var/zotero-pdf2zh/config" | rg '\\.example$' || true
```

若有输出，删掉它们并重启服务即可：

```bash
rm -f "$(brew --prefix)/var/zotero-pdf2zh/config/"*.example
brew services restart zotero-pdf2zh
```

---

## 更新策略（使用者视角）

### 1) 上游 zotero-pdf2zh 更新（自动进入 Formula）

当本仓库的 GitHub Actions 合并了上游新 Release 对应的 PR 后，你本机只需要：

```bash
brew update
brew upgrade zotero-pdf2zh
brew services restart zotero-pdf2zh
```

### 2) Python 依赖更新（例如 pdf2zh_next）

依赖更新通过 `zotero-pdf2zh-update` 完成：

```bash
zotero-pdf2zh-update
```

行为：

- 强制升级 `pdf2zh_next`
- 对比升级前后版本号
- 运行健康检查（失败会尝试回滚，并拒绝重启服务）
- 只有版本变化才会 `brew services restart zotero-pdf2zh`

另外，每次 `brew install/reinstall/upgrade zotero-pdf2zh` 后会写入 marker 文件：

- `$(brew --prefix)/var/zotero-pdf2zh/needs-deps-update`

下一次服务启动会尝试执行一次依赖更新（失败不会阻止服务启动，且会清除 marker，避免反复慢启动）。

---

## 卸载

```bash
brew services stop zotero-pdf2zh
brew uninstall zotero-pdf2zh
```

如需同时删除配置/输出/venv：

```bash
rm -rf "$(brew --prefix)/var/zotero-pdf2zh"
```

---

## 维护者指南（本仓库维护者视角）

### 自动 bump workflow（上游 Release → Formula）

- 工作流文件：`.github/workflows/update-zotero-pdf2zh.yml`
- 行为：
  - 读取 `Formula/zotero-pdf2zh.rb` 的当前 `url`/`sha256`
  - 查询上游最新 Release tag
  - 下载上游 release asset 并计算 sha256
  - 仅修改 `Formula/zotero-pdf2zh.rb`，创建 PR 并开启 squash auto-merge

### 常见问题

#### brew 安装/重装失败：keg 被占用

如果你在 `brew reinstall zotero-pdf2zh` 时遇到 “Could not rename … keg”，通常是服务仍在运行或有进程占用旧目录。先停服务再重装：

```bash
brew services stop zotero-pdf2zh
brew reinstall zotero-pdf2zh
```

#### 服务翻译时报 “API key is required”

这通常是插件选择了对应引擎（例如 DeepSeek），但配置文件里没有该引擎的 key，或配置被 `.example` 覆盖了。

排查顺序：

1) 检查 `$(brew --prefix)/var/zotero-pdf2zh/config` 下是否还存在 `*.example`（见上文），有就删
2) 在 Zotero 插件里补齐对应引擎的 key 并保存
3) `brew services restart zotero-pdf2zh`
