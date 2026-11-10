# Shared Codex / Claude Code workflow

Read `CLAUDE.md` first and follow its project rules, then read `STATUS.md`,
the current milestone in `docs/05-plan.md`, and the active ticket in `tasks/`.
`CLAUDE.md` is the shared project guidance; keep it authoritative rather than
duplicating its rules here.

Use the same handoff files in both tools:

- `STATUS.md`: current ticket, latest result, next action, and last verified
  phone state. Update at the end of each session that changes project state.
- `tasks/`: scope and acceptance criteria; keep the ticket and index consistent.
- `log/`: dated evidence, exact inputs, results, and rollback verification.

Read the latest resume section and ticket log before interpreting older status
summaries. If they disagree, check the recorded evidence and label anything
unverified. Do not infer the current phone state from an earlier test.

The outer repository tracks documentation, tools, and evidence. `src/` is
ignored and contains separate kernel repositories and build outputs. Check
`git status` and the branch in `src/ack-6.18/common` independently before any
kernel change or build. Clean driver branches and diagnostic/test branches
have different purposes; follow the branch guidance in `STATUS.md`.

When switching tools, record the outer and kernel commits, uncommitted work,
build/config/image paths and hashes, the latest test and restore result, and
the next action where relevant. Check the actual branch again on resumption.
Coordinate work through these files; avoid simultaneous changes to the same
kernel checkout or phone test session.

Project orientation alone does not start the next boot test. Phone root
operations and flashing still require the owner present per `CLAUDE.md`.
