<!-- BEGIN GPT GLOBAL RULES -->
# GPT Global Project Rules

This file is for GPT/Codex sessions in this repository. Claude-specific behavior remains in .claude/.

## Core Workflow

1. Start work by checking the Kanban board first.
2. If the team does not exist, create it with project group U2DIA Commerce AI.
3. Create or claim a ticket before substantive implementation.
4. Keep ticket status aligned with real work:
   - Backlog -> scoping only
   - Todo -> ready to start
   - In Progress -> active implementation or audit
   - Review -> verification complete, awaiting sign-off
   - Done -> accepted and closed
   - Blocked -> external dependency or missing decision
5. Archive completed tickets after outcome, verification, and artifact links are recorded.

## Kanban Rules

- Prefer the Kanban MCP server from .mcp.json.
- Team naming should follow TEAM-U2DIA-*.
- When creating a team, always set project group to U2DIA Commerce AI.
- Every substantial task should leave two traces:
  - board ticket state
  - repo artifact in docs/plans/ or docs/reports/
- If Kanban MCP is unavailable in the current runtime, state that explicitly and use a repo plan/report file as the fallback trace.

## GPT-Only Execution Rules

- These rules apply only to GPT/Codex sessions for this repository.
- Use MCP only when it helps execution. Do not invent MCP actions that are unavailable in the current runtime.
- For audits or reviews, findings come first, ordered by severity, with concrete file references.
- For implementation work, do not stop at planning if the change can be made safely in the current turn.
- Before closing a task, record:
  - what changed
  - what was verified
  - what remains blocked or manually pending

## Global Stage Policy

- Backlog: clarify scope, assumptions, dependencies, and exit criteria.
- Todo: define the smallest shippable next change and required files/tools.
- In Progress: report concrete deltas, not intentions.
- Review: validate behavior, tests, regressions, and legal/security impact where relevant.
- Blocked: name the blocker, attempted workaround, and exact next unblock action.
- Done: summarize shipped outcome and residual risks briefly.

## MCP Preference

- Preferred servers for GPT/Codex work in this repo:
  - kanban
  - ilesystem
  - git
  - 	ime
  - playwright when browser verification is needed

## Artifact Conventions

- Plans: docs/plans/YYYY-MM-DD-*.md
- Reports/closure: docs/reports/YYYY-MM-DD-*.md
- Keep artifact names tied to ticket IDs when available.
<!-- END GPT GLOBAL RULES -->

