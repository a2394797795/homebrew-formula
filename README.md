# zotero-pdf2zh Homebrew Tap

这个仓库提供 `zotero-pdf2zh` 的 Homebrew 安装方式，并补上日常运行、依赖更新和自动维护所需要的包装逻辑。

上游项目：<https://github.com/guaguastandup/zotero-pdf2zh>

这个仓库只做两件事：

- 把上游 release 打包成可安装的 Homebrew formula
- 让版本更新、基础验证和分支清理可以自动执行

这个仓库不改上游业务逻辑，也不维护 Zotero 插件本身。

## 安装

```bash
brew tap a2394797795/homebrew-formula
brew install zotero-pdf2zh
```

安装完成后会得到两个命令：

- `zotero-pdf2zh`
- `zotero-pdf2zh-update`

## 快速开始

安装后，先启动服务：

```bash
brew services start zotero-pdf2zh
```

检查服务是否正常：

```bash
curl -fsS http://127.0.0.1:47700/health
```

如果需要前台运行，使用：

```bash
zotero-pdf2zh --port 47700 --check_update false
```

## 日常使用

### 启动、停止、重启

```bash
brew services start zotero-pdf2zh
brew services stop zotero-pdf2zh
brew services restart zotero-pdf2zh
```

### 查看状态和日志

```bash
brew services list

tail -n 200 "$(brew --prefix)/var/log/zotero-pdf2zh.log"
```

### 用户命令

#### `zotero-pdf2zh`

用于启动本地服务。它会：

- 固定使用 `$(brew --prefix)/var/zotero-pdf2zh` 作为数据目录
- 固定使用 `var/zotero-pdf2zh/venv` 作为 Python 虚拟环境
- 正常启动时不强制联网升级依赖
- 在安装或升级后，根据 marker 文件触发一次依赖刷新

常见用法：

```bash
zotero-pdf2zh --port 47700 --check_update false
```

#### `zotero-pdf2zh-update`

用于刷新虚拟环境中的 Python 依赖，主要是 `pdf2zh_next`。

常见用法：

```bash
zotero-pdf2zh-update
zotero-pdf2zh-update --no-restart
zotero-pdf2zh-update --restart
```

执行内容包括：

- 更新依赖
- 执行 `pip check`
- 验证 `pdf2zh_next` 可导入
- 验证 `server.py --help`
- 更新失败时尝试回滚
- 只有依赖版本变化时才重启服务

## 配置和文件位置

### 程序文件

Homebrew 安装内容位于：

```bash
$(brew --prefix)/Cellar/zotero-pdf2zh/<version>/libexec
```

这里是只读安装目录，不建议手动修改。

### 数据目录

运行时数据位于：

```bash
$(brew --prefix)/var/zotero-pdf2zh
```

主要内容包括：

- `config/`：配置文件
- `translated/`：输出目录
- `venv/`：Python 虚拟环境
- `needs-deps-update`：安装或升级后的一次性依赖刷新标记

### 日志文件

```bash
$(brew --prefix)/var/log/zotero-pdf2zh.log
```

### 配置文件

推荐直接通过 Zotero 插件写入配置。常见文件位置：

- `$(brew --prefix)/var/zotero-pdf2zh/config/config.json`
- `$(brew --prefix)/var/zotero-pdf2zh/config/config.toml`
- `$(brew --prefix)/var/zotero-pdf2zh/config/venv.json`

有一个细节需要注意：不要在可写配置目录里保留 `*.example` 文件。上游启动时会把它们当成模板，可能覆盖真实配置。

检查方式：

```bash
ls -1 "$(brew --prefix)/var/zotero-pdf2zh/config" | rg '\.example$' || true
```

清理方式：

```bash
rm -f "$(brew --prefix)/var/zotero-pdf2zh/config/"*.example
brew services restart zotero-pdf2zh
```

## 更新与验证

这里有两类更新。

### 1. 更新 formula 版本

这一层对应上游 release 版本，例如 `3.x -> 4.x`。

执行方式：

```bash
brew update
brew upgrade zotero-pdf2zh
brew services restart zotero-pdf2zh
```

如果你要强制重装当前版本：

```bash
brew reinstall zotero-pdf2zh
brew services restart zotero-pdf2zh
```

### 2. 更新 Python 依赖

这一层对应虚拟环境中的依赖更新，例如 `pdf2zh_next`。

执行方式：

```bash
zotero-pdf2zh-update
```

如果只更新依赖，不立即重启：

```bash
zotero-pdf2zh-update --no-restart
```

### 验证更新是否成功

建议按下面顺序检查。

#### A. 看 formula 版本

```bash
brew info zotero-pdf2zh
brew list --versions zotero-pdf2zh
ruby -e 'f = Formula["zotero-pdf2zh"]; puts f.stable.url'
```

#### B. 看当前 Cellar 版本

```bash
ls -1 "$(brew --cellar zotero-pdf2zh)"
```

#### C. 看服务是否可用

```bash
brew services restart zotero-pdf2zh
curl -fsS http://127.0.0.1:47700/health
```

正常情况下应该返回 JSON，而不是报错或 404。

#### D. 看依赖是否已经更新

```bash
zotero-pdf2zh-update --no-restart

VENV="$(brew --prefix)/var/zotero-pdf2zh/venv"
"$VENV/bin/python" -m pip show pdf2zh_next
"$VENV/bin/python" -m pip check
```

如果你要看完整依赖列表：

```bash
VENV="$(brew --prefix)/var/zotero-pdf2zh/venv"
"$VENV/bin/python" -m pip freeze | sort
```

#### E. 看当前命令实际指向哪里

```bash
which zotero-pdf2zh
readlink "$(which zotero-pdf2zh)" || true
brew --prefix zotero-pdf2zh
brew --cellar zotero-pdf2zh
```

### 常用验收命令

如果你刚执行过升级，通常跑下面这一组就够了：

```bash
brew update
brew upgrade zotero-pdf2zh
zotero-pdf2zh-update --no-restart
brew services restart zotero-pdf2zh

brew list --versions zotero-pdf2zh
ls -1 "$(brew --cellar zotero-pdf2zh)"
curl -fsS http://127.0.0.1:47700/health

VENV="$(brew --prefix)/var/zotero-pdf2zh/venv"
"$VENV/bin/python" -m pip show pdf2zh_next
"$VENV/bin/python" -m pip check
```

## 卸载

```bash
brew services stop zotero-pdf2zh
brew uninstall zotero-pdf2zh
```

如果还要删除配置、输出和虚拟环境：

```bash
rm -rf "$(brew --prefix)/var/zotero-pdf2zh"
```

## 常见问题

### `brew reinstall` 提示 keg 被占用

先停服务，再重装：

```bash
brew services stop zotero-pdf2zh
brew reinstall zotero-pdf2zh
```

### 启动后提示 `API key is required`

一般先查这三项：

1. `config/` 目录里是否残留 `*.example`
2. Zotero 插件里是否已经保存对应引擎的 key
3. 服务是否已经重启

可以先直接执行：

```bash
rm -f "$(brew --prefix)/var/zotero-pdf2zh/config/"*.example
brew services restart zotero-pdf2zh
```

## 维护者说明

### 自动化流程

主流程在 `.github/workflows/update-zotero-pdf2zh.yml`，负责：

- 定时检查上游最新 stable release
- 更新 `Formula/zotero-pdf2zh.rb`
- 执行 `scripts/smoke_test.sh`
- 创建或更新 PR
- 自动 squash merge
- 清理自动生成的 bump 分支

兜底流程在 `.github/workflows/cleanup-bump-branches.yml`，只做一件事：

- PR 合并后，如果 bump 分支还存在，就再删一次

### 手动触发更新

如果你不想等定时任务，可以手动触发：

```bash
gh workflow run 'Update zotero-pdf2zh' -R a2394797795/homebrew-formula --ref main
gh run list -R a2394797795/homebrew-formula --limit 5
gh run watch -R a2394797795/homebrew-formula <run-id>
```

重点看这几个阶段：

- `Update formula from latest upstream release`
- `Validate updated formula`
- `Create pull request`
- `Merge pull request`

有新版本时，预期结果是：

- `Formula/zotero-pdf2zh.rb` 被更新
- 自动创建并合并 `bump-zotero-pdf2zh-*` PR
- 远端不残留 bump 分支

没有新版本时，预期结果是：

- workflow 正常结束
- 不创建新 PR
- `Formula/zotero-pdf2zh.rb` 不变化

### 本地验证

先准备 GitHub CLI 凭证：

```bash
export GH_TOKEN="$(gh auth token)"
gh auth status
```

然后在仓库根目录执行：

```bash
./scripts/update_formula.sh
./scripts/smoke_test.sh
```

这两个脚本分别负责：

- 从上游最新 release 更新 formula
- 用临时 tap 真实安装并检查 `/health`

如果你只想先看 formula 会不会变化：

```bash
git diff -- Formula/zotero-pdf2zh.rb
```

本地验证后，建议再看：

```bash
git status -sb
git diff -- Formula/zotero-pdf2zh.rb
```

预期是：

- 上游没新版本时，没有 diff
- 上游有新版本时，只改 `Formula/zotero-pdf2zh.rb`

### 仓库关键文件

- `Formula/zotero-pdf2zh.rb`：Homebrew formula 和服务包装逻辑
- `scripts/update_formula.sh`：根据上游 release 更新 formula
- `scripts/smoke_test.sh`：临时安装并做基本健康检查
- `.github/workflows/update-zotero-pdf2zh.yml`：主更新流程
- `.github/workflows/cleanup-bump-branches.yml`：分支清理兜底流程
