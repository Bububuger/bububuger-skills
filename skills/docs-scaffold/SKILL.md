---
name: docs-scaffold
description: "Initialize or restructure a project's documentation structure using a battle-tested agent harness template. Creates AGENTS.md, ARCHITECTURE.md, and a full docs/ tree (design-docs, exec-plans, product-specs, references, generated). Use this skill whenever the user asks to set up project documentation, scaffold docs, create a docs structure, initialize project docs, restructure documentation, 初始化文档, 文档结构, 项目文档骨架, or wants an organized documentation layout for an AI-agent-friendly codebase."
---

# Documentation Scaffold

Set up or restructure a project's documentation for AI-agent-friendly collaboration. The template adapts to the project — not every project needs every file.

## The Full Template

This is the maximum structure. You will select a subset based on what the project actually needs.

```
PROJECT_ROOT/
├── AGENTS.md                    # Agent roles, capabilities, coordination rules
├── ARCHITECTURE.md              # System architecture overview
└── docs/
    ├── design-docs/
    │   ├── index.md             # Design doc registry
    │   ├── core-beliefs.md      # Technical principles and values
    │   └── ...
    ├── exec-plans/
    │   ├── active/              # Plans currently being executed
    │   ├── completed/           # Archived completed plans
    │   └── tech-debt-tracker.md # Known technical debt registry
    ├── generated/               # Auto-generated docs (DB schema, API specs, etc.)
    ├── product-specs/
    │   ├── index.md             # Product spec registry
    │   └── ...
    ├── references/              # Categorized reference docs (see Step 5)
    ├── DESIGN.md                # Design system and UI/UX guidelines
    ├── FRONTEND.md              # Frontend architecture and conventions
    ├── PLANS.md                 # High-level roadmap and planning
    ├── PRODUCT_SENSE.md         # Product thinking, user empathy, priorities
    ├── QUALITY_SCORE.md         # Quality metrics and scoring criteria
    ├── RELIABILITY.md           # SLA, monitoring, incident response
    └── SECURITY.md              # Security policies and threat model
```

## Execution Steps

### Step 1: Quick Project Profile

Build a project profile WITHOUT reading source code line by line. Read only these lightweight signals:

1. **Manifest files** — `package.json`, `Cargo.toml`, `mix.exs`, `pyproject.toml`, `go.mod`, etc. → tech stack, project name, key dependencies
2. **Top-level structure** — `ls` the root and one level deep → identify major directories (src/, app/, lib/, frontend/, api/, etc.)
3. **Existing docs** — glob for `**/*.md`, `**/docs/**`, `**/wiki/**`, `**/*.rst` → what documentation already exists
4. **Config signals** — `.env.example`, `docker-compose.yml`, `Dockerfile`, CI configs → deployment and infra clues
5. **Schema signals** — glob for `**/migrations/**`, `**/schema.*`, `**/prisma/**`, `**/ecto/**` → database presence

From these signals, classify the project:

| Signal | Classification |
|--------|---------------|
| Has `frontend/`, `app/`, React/Vue/Svelte deps | **Has frontend** → include FRONTEND.md, DESIGN.md |
| Pure CLI tool, library, API-only | **No frontend** → skip FRONTEND.md, DESIGN.md |
| Has DB migrations, ORM models | **Has database** → include generated/db-schema.md |
| No database signals | **No database** → skip generated/db-schema.md |
| Has auth code, security headers | **Security-relevant** → include SECURITY.md |
| Simple script or internal tool | **Low security surface** → skip SECURITY.md |

### Step 2: Decide What to Create

Based on the profile, select which files and directories to create. Present the plan to the user:

```
Based on project analysis, I'll create:

✓ AGENTS.md
✓ ARCHITECTURE.md
✓ docs/design-docs/ (index.md, core-beliefs.md)
✓ docs/exec-plans/ (active/, completed/, tech-debt-tracker.md)
✓ docs/product-specs/ (index.md)
✓ docs/references/
✓ docs/PLANS.md
✓ docs/QUALITY_SCORE.md
✓ docs/RELIABILITY.md

Skipping (no frontend detected):
✗ docs/FRONTEND.md
✗ docs/DESIGN.md

Skipping (no database detected):
✗ docs/generated/db-schema.md

Proceed? Or adjust?
```

Wait for user confirmation before creating files.

### Step 3: Generate Content

Content comes from **project signals**, not from reading every source file. This keeps the skill fast even on large codebases.

#### AGENTS.md — from project context

```markdown
# Agents

## Roles

| Agent | Scope | Notes |
|-------|-------|-------|
| Human | All | Final authority on product decisions |
| Claude Code | Implementation, review, planning | Primary coding agent |

## Coordination Rules

- Architectural changes require a design doc in `docs/design-docs/`
- New work starts with an exec plan in `docs/exec-plans/active/`
- Completed plans move to `docs/exec-plans/completed/`
- Reference docs for key dependencies live in `docs/references/`
```

Adapt the agents table based on what you find (e.g., CI bots, other AI agents, team structure clues in CODEOWNERS).

#### ARCHITECTURE.md — from directory structure + manifests

Infer architecture from the project's directory layout, dependency graph, and config files. Include:
- System overview
- Tech stack (concrete versions from lock files)
- Component map (what each top-level directory does)
- Data flow (if discernible from config/schema)
- Deployment (if docker/CI configs exist)

Mark unknowns as "TBD — needs team input" rather than guessing.

#### docs/exec-plans/tech-debt-tracker.md — from quick grep

Run a fast grep for `TODO`, `FIXME`, `HACK`, `XXX` across the codebase to seed the tracker. Don't read each file — just collect the grep hits:

```markdown
# Tech Debt Tracker

| ID | Area | Description | Impact | Effort | Status |
|----|------|-------------|--------|--------|--------|
| TD-001 | auth | TODO: rate limiting not implemented | H | M | Open |
| TD-002 | api | FIXME: pagination breaks above 1000 | M | L | Open |
```

#### Other docs/ files — templates with project context

For files like PLANS.md, QUALITY_SCORE.md, RELIABILITY.md, PRODUCT_SENSE.md — create templates with section headers populated from what the project profile reveals. Don't leave them completely blank, but don't fabricate content either. A good middle ground:

```markdown
# Reliability

## Current State
[Project name] is deployed via [Docker/K8s/serverless — from config signals].
Monitoring: TBD
Alerting: TBD

## SLA Targets
TBD — needs team input

## Incident Response
TBD — needs team input
```

### Step 4: Populate references/

The `references/` directory holds reference documents categorized by topic. Do NOT hardcode categories — derive them from what the project actually contains.

**How to populate:**

1. **Scan for existing docs** — if the project already has scattered reference files (READMEs in subdirectories, wiki pages, API docs, style guides), classify and move/copy them here
2. **Key dependency docs** — for the 3-5 most important dependencies, check for `llms.txt` endpoints (e.g., `https://docs.example.com/llms.txt`). If available, fetch and save. If not, create a brief pointer file with the dependency's purpose and official docs link
3. **Name files by topic, not by format** — use descriptive names like `authentication-flow.md`, `deployment-guide.md`, `api-conventions.md` rather than `reference-1.md`

Examples of how references/ might look for different project types:

```
# A web app with Supabase + Next.js
references/
├── supabase-llms.txt
├── nextjs-llms.txt
└── auth-flow.md

# An Elixir umbrella project
references/
├── phoenix-llms.txt
├── ecto-patterns.md
└── deployment-guide.md

# A Rust CLI tool
references/
├── clap-llms.txt
└── release-process.md
```

### Step 5: Handle Restructuring

When the project already has documentation:

1. **Inventory** — list all existing docs with their paths
2. **Classify** — map each to the template category it belongs in
3. **Present migration plan** — show the user before moving anything:
   ```
   Migration Plan:
   docs/api.md          → docs/generated/api-spec.md
   CONTRIBUTING.md      → (keep at root, reference from AGENTS.md)
   design/*.md          → docs/design-docs/
   notes/arch-notes.md  → fold into ARCHITECTURE.md
   [new]                → AGENTS.md (generated)
   [new]                → docs/exec-plans/tech-debt-tracker.md (from TODOs)
   ```
4. **Execute only after confirmation**
5. **Update internal links** after migration
6. **Keep originals** until user confirms the migration is correct

## Document Templates

### Index (for registries)

```markdown
# [Category] Index

| Document | Status | Last Updated | Summary |
|----------|--------|--------------|---------|
| [name](./name.md) | Active | YYYY-MM-DD | One-line summary |
```

### Exec Plan

```markdown
# [Plan Title]

**Status**: Active | Completed | Abandoned
**Created**: YYYY-MM-DD
**Owner**: [who]

## Goal
[What and why]

## Steps
- [ ] Step 1
- [ ] Step 2

## Risks
- Risk 1: mitigation

## Done Criteria
- [ ] Criterion 1
```

### Tech Debt Tracker

```markdown
# Tech Debt Tracker

| ID | Area | Description | Impact | Effort | Status |
|----|------|-------------|--------|--------|--------|
| TD-001 | [area] | [description] | H/M/L | H/M/L | Open |
```

## Ground Rules

- **Never overwrite** existing files without explicit user confirmation
- **Never browse all source code** — use manifest files, directory structure, config files, and quick greps. The skill must stay fast on large monorepos
- **Adapt to the project** — skip files/dirs that don't apply. A CLI tool doesn't need FRONTEND.md. A static site doesn't need RELIABILITY.md. Use judgment
- **Real content over empty templates** — prefer a 3-line file with real info over a 50-line template full of placeholders
- **Present the plan first** — always show the user what you intend to create/move before doing it
