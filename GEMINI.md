# Workspace Rules for Tier Project Management

## 1. Mandatory Planning & Confirmation Gate
- **NEVER** edit, create, or modify any project code files (using `replace_file_content`, `write_to_file`, or modifying commands) without first presenting an `implementation_plan.md` artifact and waiting for explicit user confirmation.
- **Strict Workflow for all requests involving changes**:
  1. **Research Phase**: Use read-only tools (`view_file`, `grep_search`, `find_by_name`, `list_dir`) to thoroughly investigate the codebase.
  2. **Plan Phase**: Create or update `implementation_plan.md` detailing the problem, proposed changes, affected files, and verification plan.
  3. **STOP & Wait**: Do not call any modification tools. End turn and request explicit user confirmation on the plan.
  4. **Execution Phase**: Only after the user confirms/approves the plan, proceed to edit files, run tests (`flutter test`, `dart analyze`), and commit/push changes.

## 2. Testing & Quality Assurance
- Always run `dart analyze` and `flutter test` before committing any code changes.
- Ensure 0 static analysis errors and 100% passing tests on every commit.

## 3. Communication Style
- Keep responses concise and focused.
- Create clickable `file:///` links for referenced files and code symbols.

## 4. Pure KISS, DRY, and YAGNI Principles (Codebase & App)

### 1. KISS (Keep It Simple & Playable)
- **Codebase**: Write the simplest, most direct working Flutter code. Avoid complex state machines, micro-factories, or multi-step prompt pipelines when simple Provider mixins and single-pass prompts work.
- **App & AI**: 
  - **The Playtest Rule**: If a player or QA tester cannot see, hear, or feel it on screen during gameplay, rephrase it into an observable deliverable.
  - **Cohesive Playable Units**: Group mechanics and game feel (controls, physics, SFX, animations, particle cues) into single, unified cards. Do NOT split a feature into artificial technical micro-tickets.
  - **Punchy Titles**: Keep card titles short and direct (2–4 plain English words).

### 2. DRY (Don't Repeat Yourself / Single Source of Truth)
- **Codebase**: 
  - Centralize shared tokens (theme, tier colors, prompts).
  - **Rule of Three**: Only create shared abstractions after writing the exact same logic three times.
- **App & AI**: 
  - **Single Source of Truth**: Every system, mechanic, and deliverable lives under exactly one parent in the 4-tier document hierarchy (Project, Release, Epic, Feature). No duplicate cards scattered across sibling epics.
  - **Automatic Rollups**: Hours, checklist counts, and progress rollup dynamically from Feature Checklist Steps and Playable Stages all the way up to Project (Tier 1) without manual duplicate entry.

### 3. YAGNI (You Aren't Gonna Need It / Scope Discipline)
- **Codebase**: Build strictly what the immediate feature requires today. Strip out hypothetical future-proofing, extra database columns, or unneeded packages before writing code.
- **App & AI**: 
  - **Milestone Scope Discipline**: Breakdowns generate *only* the immediate next-step deliverables suited for the active release scope (Prototype, MVP, Vertical Slice, Standard).
  - **Focus Mode**: Dim out-of-scope sibling tasks to prevent scope creep during production.

## 5. Scope & Goal Formatting Rule
Whenever writing or revising any Scope, Goal, or Objective section (across Epics, PRDs, task tickets, or design docs), follow these constraints:
- **No Paragraphs**: Never write scope or goals as dense narrative text. Always use this structured 3-part layout:
  - **Goal**: Exactly one plain-English sentence stating what is being built/done and why.
  - **In Scope**: A concise bulleted list of the specific systems, features, or assets included.
  - **Done When**: Clear, practical conditions for when the work is considered complete.
- **Tone**: Write like a practical developer talking to a teammate. Keep it direct and natural.
- **Banned Jargon**: Never use corporate filler or vague buzzwords (e.g., *leverage*, *unified*, *end-to-end loop*, *staging*, *validate*, *deliver*, *synergy*, *seamlessly*). State the actual concrete action instead.
