# ThinkForge Workspace Instructions

ThinkForge connects ChatGPT to this local repo through MCP tools. Treat the active workspace root as the source of truth.

## Fast repo navigation

- Start with `open_current_workspace` using `include_tree=false` unless a tree is actually needed.
- Do not call inventory/resource discovery tools during normal code work unless the user explicitly asks what tools are available.
- Prefer `repo_search` first for task-oriented code discovery. It returns compact ranked files, snippets, and suggested read ranges.
- Use lower-level `repo_inspector` only when `repo_search` is too broad or you specifically need CodeGraph, RTK, or rg follow-up details.
- Use `repo_inspector` CodeGraph actions (`codegraph_query`, `codegraph_node`, `codegraph_callers`, `codegraph_callees`, `codegraph_impact`) for symbols, references, callers/callees, structure, and impact checks.
- Use `repo_inspector rtk_grep` when RTK grep is useful for scoped code discovery. Do not describe RTK as semantic search unless richer RTK semantic actions are exposed.
- Use `search` or `repo_inspector rg_search` for exact text, error strings, filenames, config keys, and known literals.
- Read the smallest useful line ranges after `repo_search`, CodeGraph, rg, or RTK identifies likely files.
- Avoid dumping full logs, full command output, full repo trees, or full tool inventories into chat.

## Editing and verification

- Keep changes scoped to the user request.
- Use Git status/diff to review changes before reporting.
- Use verification commands only when needed and summarize results compactly.
- For Git cleanup, back up old Git control files outside the workspace before starting fresh.
