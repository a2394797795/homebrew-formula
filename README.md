# Homebrew Tap: zotero-pdf2zh

这个仓库把上游 [`guaguastandup/zotero-pdf2zh`](https://github.com/guaguastandup/zotero-pdf2zh) 的 `server.zip` 打包成一个可通过 Homebrew 安装和管理的本地服务。

边界很明确：

- 不改上游源码，只做 Homebrew 适配
- 配置、输出、虚拟环境都放在 `$(brew --prefix)/var/zotero-pdf2zh`
- 版本更新尽量自动化，坏更新必须在 CI 被拦下
- 日常启动尽量稳定，不在每次启动时强制联网升级依赖

## 安装

```bash
brew tap a2394797795/homebrew-formula
brew install zotero-pdf2zh
```

安装后可执行文件在：

- `$(brew --prefix)/bin/zotero-pdf2zh`
- `$(brew --prefix)/bin/zotero-pdf2zh-update`

## 用户端命令

这个 tap 实际提供的命令只有 2 个：

### 1) `zotero-pdf2zh`

启动本地服务。它是上游 `server.py` 的包装器，会保证：

- 使用固定的持久化目录
- 使用 `var/zotero-pdf2zh/venv`
- 正常启动时不强制更新依赖
- 首次安装或升级后，按 marker 触发一次依赖刷新尝试

常见用法：

```bash
zotero-pdf2zh --port 47700 --check_update false
```

### 2) `zotero-pdf2zh-update`

只负责刷新 Python 依赖，当前核心是 `pdf2zh_next`。

常见用法：

```bash
zotero-pdf2zh-update
zotero-pdf2zh-update --no-restart
zotero-pdf2zh-update --restart
```

行为：

- 升级依赖
- 做 `pip check` 和导入健康检查
- 校验 `server.py --help`
- 失败时尝试回滚
- 只有依赖版本变化时才重启服务

## 哪些命令算冗余？

不冗余的只有两类：

- tap 自己提供的命令：`zotero-pdf2zh`、`zotero-pdf2zh-update`
- Homebrew 通用管理命令：`brew install`、`brew upgrade`、`brew services ...`

其中：

- `brew services start/stop/restart zotero-pdf2zh` 不是本仓库自定义命令，而是 Homebrew 的标准服务管理入口
- `zotero-pdf2zh-update --restart` 和 `brew services restart zotero-pdf2zh` 目标有重叠，但不完全重复：前者是“先更新依赖，再按需重启”，后者是“直接重启服务”

所以当前命令面是精简的，没有明显需要再删的重复命令。

## 日常使用

### 启动 / 停止 / 重启

```bash
brew services start zotero-pdf2zh
brew services stop zotero-pdf2zh
brew services restart zotero-pdf2zh
```

### 查看状态 / 日志

```bash
brew services list

tail -n 200 "$(brew --prefix)/var/log/zotero-pdf2zh.log"
```

### 前台运行

```bash
zotero-pdf2zh --port 47700 --check_update false
```

## 文件位置

### 只读程序本体

```bash
$(brew --prefix)/Cellar/zotero-pdf2zh/<version>/libexec
```

### 可写数据目录

```bash
$(brew --prefix)/var/zotero-pdf2zh
```

里面主要有：

- `config/`：配置
- `translated/`：输出目录
- `venv/`：Python 虚拟环境
- `needs-deps-update`：安装/升级后的一次性依赖刷新标记

### 日志

```bash
$(brew --prefix)/var/log/zotero-pdf2zh.log
```

## 配置说明

推荐直接在 Zotero 插件里配置，插件会把设置写入：

- `$(brew --prefix)/var/zotero-pdf2zh/config/config.json`
- `$(brew --prefix)/var/zotero-pdf2zh/config/config.toml`
- `$(brew --prefix)/var/zotero-pdf2zh/config/venv.json`

注意：不要在可写配置目录里保留 `*.example` 文件。上游会把它们当成模板源，可能在启动时覆盖真实配置。

检查：

```bash
ls -1 "$(brew --prefix)/var/zotero-pdf2zh/config" | rg '\.example$' || true
```

清理：

```bash
rm -f "$(brew --prefix)/var/zotero-pdf2zh/config/"*.example
brew services restart zotero-pdf2zh
```

## 更新怎么启动

更新分两层。

### 1) 更新 Homebrew Formula 版本

这是上游 `zotero-pdf2zh` 的版本更新，例如 `3.x -> 4.x`。

触发方式：

```bash
brew update
brew upgrade zotero-pdf2zh
brew services restart zotero-pdf2zh
```

如果你想强制重装当前 formula：

```bash
brew reinstall zotero-pdf2zh
brew services restart zotero-pdf2zh
```

### 2) 更新 Python 依赖

这是虚拟环境里的依赖更新，例如 `pdf2zh_next`。

触发方式：

```bash
zotero-pdf2zh-update
```

如果你只想更新依赖、暂时不重启：

```bash
zotero-pdf2zh-update --no-restart
```

## 如何在本地验证更新成功

建议按下面的顺序验，能同时覆盖 formula、本体、服务和依赖。

### A. 验证 Homebrew Formula 版本

```bash
brew info zotero-pdf2zh
brew list --versions zotero-pdf2zh
```

还可以直接看安装源：

```bash
ruby -e 'f = Formula["zotero-pdf2zh"]; puts f.stable.url'
```

### B. 验证当前 Cellar 版本

```bash
ls -1 "$(brew --cellar zotero-pdf2zh)"
```

### C. 验证服务是否正常

```bash
brew services restart zotero-pdf2zh
curl -fsS http://127.0.0.1:47700/health
```

预期应该返回类似 JSON，而不是 404。

### D. 验证依赖是否更新

先执行：

```bash
zotero-pdf2zh-update --no-restart
```

然后查看虚拟环境里的关键包：

```bash
VENV="$(brew --prefix)/var/zotero-pdf2zh/venv"
"$VENV/bin/python" -m pip list
"$VENV/bin/python" -m pip show pdf2zh_next
"$VENV/bin/python" -m pip check
```

如果你想保存一份完整依赖快照：

```bash
VENV="$(brew --prefix)/var/zotero-pdf2zh/venv"
"$VENV/bin/python" -m pip freeze | sort
```

### E. 验证当前实际运行的是哪一套程序

```bash
which zotero-pdf2zh
readlink "$(which zotero-pdf2zh)" || true
```

以及：

```bash
brew --prefix zotero-pdf2zh
brew --cellar zotero-pdf2zh
```

## 一个推荐的本地验收流程

如果你刚执行完升级，建议直接跑这一组：

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

如果连配置、输出、虚拟环境一起删：

```bash
rm -rf "$(brew --prefix)/var/zotero-pdf2zh"
```

## 自动化维护说明

主流程在 `.github/workflows/update-zotero-pdf2zh.yml`：

- 每天检查上游 stable release
- 自动更新 `Formula/zotero-pdf2zh.rb`
- 自动执行 `scripts/smoke_test.sh`
- 自动建 PR
- 自动 squash merge
- 自动清理 `bump-zotero-pdf2zh-*` 分支

兜底清理在 `.github/workflows/cleanup-bump-branches.yml`：

- 只有在 PR 关闭后才触发
- 只负责“如果分支还没删掉，就再删一次”
- 已经是纯兜底，不承担主流程逻辑

## 维护者：如何手动触发自动更新闭环

如果你要手动触发仓库自动更新，而不是等定时任务：

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

如果是“有新版本”的场景，成功后应该看到：

- `Formula/zotero-pdf2zh.rb` 被自动改到新 release
- 自动创建并合并 `bump-zotero-pdf2zh-*` PR
- 远端最终只保留 `main`，不残留 bump 分支

如果是“没有新版本”的场景，成功后应该看到：

- workflow 直接结束
- 不创建新 PR
- 不修改 `Formula/zotero-pdf2zh.rb`

## 维护者：如何本地验证自动化逻辑

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

含义分别是：

- `./scripts/update_formula.sh`：读取上游最新 release，更新 `Formula/zotero-pdf2zh.rb`
- `./scripts/smoke_test.sh`：把当前 formula 放进临时 tap，真实安装、启动服务、检查 `/health`

如果你只想看这次会不会改 formula，可以先执行：

```bash
git diff -- Formula/zotero-pdf2zh.rb
```

本地验证通过后，再看：

```bash
git status -sb
git diff -- Formula/zotero-pdf2zh.rb
```

预期：

- 上游没新版本时：没有 diff
- 上游有新版本时：只改 `Formula/zotero-pdf2zh.rb`

## 常见问题

### `brew reinstall` 时报 keg 被占用

先停服务再重装：

```bash
brew services stop zotero-pdf2zh
brew reinstall zotero-pdf2zh
```

### 翻译时报 `API key is required`

优先排查：

1. `config/` 里是否残留 `*.example`
2. Zotero 插件里是否真的保存了对应引擎的 key
3. 服务是否已经重启

可直接执行：

```bash
rm -f "$(brew --prefix)/var/zotero-pdf2zh/config/"*.example
brew services restart zotero-pdf2zh
```
