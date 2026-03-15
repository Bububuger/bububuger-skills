# Bububuger Skills

A Claude Code plugin packaging project governance skills.

## Skills

| Skill | Purpose | Typical Trigger |
|-------|---------|-----------------|
| `project-reviewer` | Multi-role codebase audit (12 perspectives) | `/project-reviewer`, "审视项目", "code audit" |
| `docs-scaffold` | Initialize/restructure project documentation | `/docs-scaffold`, "初始化文档", "scaffold docs" |
| `review-dispatcher` | Dispatch review findings to issue trackers | `/review-dispatcher`, "派发", "dispatch findings" |

## Workflow Chain

```
project-reviewer → PROJECT_REVIEW_REPORT.md → review-dispatcher → Linear/Plane/GitHub Issues
                                                docs-scaffold → ARCHITECTURE.md, docs/ tree
```

## Development

Each skill is self-contained under `skills/<name>/SKILL.md`. Edit the SKILL.md directly — it is the skill's interface and implementation.
