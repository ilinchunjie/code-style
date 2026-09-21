---
name: code-style-lang
description: Language-specific coding conventions. Use when writing, editing, or reviewing files that match the paths below. Replace this template before publishing.
paths:
  - "**/*.<ext>"
---

# code-style-lang

Before publishing:

1. Rename the plugin directory to `plugins/code-style-<id>/`
2. Rename this skill directory to `skills/code-style-<id>/`
3. Set `name` to `code-style-<id>` (must match the directory name)
4. Set `paths` to the language file globs
5. Fill in [references/style.md](references/style.md)
6. Register `id` and `path` under `languages` in repo-root `manifest.json`

When active:

1. Also follow installed `code-style-common`
2. If this pack conflicts with the common pack, this pack wins
3. Read [references/style.md](references/style.md) and follow it
