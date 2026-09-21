# code-style

给 Cursor、Claude Code、Codex 用的代码规范 skill。公共规范与语言包彼此独立；在目标项目根目录执行一条命令即可安装，不必先克隆本仓库。

## 一键安装

在目标项目根目录执行：

```powershell
irm https://raw.githubusercontent.com/ilinchunjie/code-style/main/scripts/install.ps1 | iex
```

```bash
curl -fsSL https://raw.githubusercontent.com/ilinchunjie/code-style/main/scripts/install.sh | sh
```

默认安装公共包 `code-style-common`，以及 `manifest.json` 里已登记的全部语言包（目前为 `csharp`）。这两条命令从 GitHub `main` 拉取脚本和 zip，需要先把本仓库推上去。

## 装到哪里

| Agent | 目录 |
| --- | --- |
| Cursor | `.agents/skills/` |
| Codex | `.agents/skills/` |
| Claude Code | `.claude/skills/` |

再次执行同一条命令会覆盖更新。安装状态写在项目根目录的 `.code-style.json`。

## 参数

远程执行时用环境变量传参。

| 变量 | 含义 | 默认 |
| --- | --- | --- |
| `CODE_STYLE_TARGET` | 目标项目根目录 | 当前工作目录 |
| `CODE_STYLE_AGENTS` | `cursor`、`claude`、`codex`，逗号分隔 | 三者都装 |
| `CODE_STYLE_LANGUAGES` | 语言包 id，逗号分隔 | manifest 中已登记的全部 |
| `CODE_STYLE_UNINSTALL` | 设为 `1` 时卸载本工具写入的 skill 和 `.code-style.json` | 不卸载 |
| `GH_TOKEN` 或 `GITHUB_TOKEN` | 私有仓库下载 zip 时的访问令牌 | 公开仓库不需要 |

PowerShell 示例：

```powershell
$env:CODE_STYLE_AGENTS = 'cursor,claude'
$env:CODE_STYLE_LANGUAGES = 'csharp'
irm https://raw.githubusercontent.com/ilinchunjie/code-style/main/scripts/install.ps1 | iex
```

```powershell
$env:CODE_STYLE_UNINSTALL = '1'
irm https://raw.githubusercontent.com/ilinchunjie/code-style/main/scripts/install.ps1 | iex
```

Bash 示例：

```bash
CODE_STYLE_AGENTS=cursor,codex \
  curl -fsSL https://raw.githubusercontent.com/ilinchunjie/code-style/main/scripts/install.sh | sh
```

在本仓库内调试时，直接运行 `scripts/install.ps1` 或 `scripts/install.sh`，会使用本地文件，不下载 zip。

## 新增一种语言

1. 复制 `plugins/_template-language/` 为 `plugins/code-style-<id>/`
2. 把 skill 目录和 `SKILL.md` 里的 `name` 改成 `code-style-<id>`，并填写 `paths`
3. 在 `skills/code-style-<id>/references/style.md` 写该语言规则（与公共规范冲突时以语言包为准）
4. 在 `manifest.json` 的 `languages` 中登记，例如：

```json
"languages": {
  "typescript": {
    "id": "code-style-typescript",
    "path": "plugins/code-style-typescript/skills/code-style-typescript"
  }
}
```

推到 `main` 后，在目标项目再跑一次安装命令即可更新。
