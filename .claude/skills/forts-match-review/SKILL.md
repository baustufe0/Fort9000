---
name: forts-match-review
description: Analyse a Forts match the user played against the FORT 9000 AI, archive the log and (when asked) retrain. Use when the user says they played a match/round, mentions a new log.txt, or asks to evaluate or train.
---

# Forts match review

The user plays Forts against the FORT 9000 AI and asks for an analysis. Background lives in the repo docs; read
only what the match needs:
- [.dev/docs/testing.md](../../../.dev/docs/testing.md) – where the log is, what every log line means, plausibility checks.
- `.dev/docs/maps/<map>.md` – the current state of the plan that was played (what to expect, what is untested).
- `.dev/docs/history/<plan>.md` – earlier test matches of that plan, to compare with.

## Steps

1. **List the matches** in the current log (read-only; reads `<Forts>/users/<id>/log.txt`, UTF-16 is handled):
   ```bash
   py .claude/skills/forts-match-review/summary.py
   ```
   If the log's modification time is unchanged since the last analysis, there is no new match: say so (Forts still
   open? match not finished? log renamed?). Each listed match shows map, plan, difficulty, winner (2 = AI), length.
2. **Details of the new match** (`--match N`, `-1` = last):
   ```bash
   py .claude/skills/forts-match-review/summary.py --match -1
   ```
   It prints the `END` line, shots, metal/energy/mines per side, devices lost, when each device was placed (both
   sides), build errors, `GAVE_UP`/`SKIPPED`/`ERROR` and the `THINK` trace. For more, convert a copy into the scratchpad
   (`iconv -f UTF-16LE -t UTF-8 log.txt | tr -d '\r'`) and grep: `UNLINK s=2` for the order in which struts fell,
   `FIREWAIT`/`FIRETRY` for weapons that did not fire, `UNSTABLE`/`STRESS`/`SHAPE` for refused devices (see
   [.dev/docs/debugging.md](../../../.dev/docs/debugging.md)).
3. **Check plausibility** (.dev/docs/testing.md): aborted match (no `RESULT`, < 1 min), a player who barely fired, the same
   action given up across matches (plan bug). Ask before training on a doubtful match.
4. **Compare with the map file**: did the plan build what `.dev/docs/maps/<map>.md` expects, in time? What decided the
   match (how the AI's fort fell, what the player built and when, what the AI hit)?
5. **Archive the log**: `py .dev/tools/train.py collect` (always; Forts overwrites `log.txt` on the next start).
   Retrain only when the user asks: `py .dev/tools/train.py` (collect + train, rewrites `ai/strategy.lua`); `report` shows
   wins per plan without writing.
6. **Record it** when the user wants the plan changed or the test recorded: the test goes into
   `.dev/docs/history/<plan>.md`, what changes in the current state into `.dev/docs/maps/<map>.md` (CLAUDE.md workflow).

## Report

Answer in English, short: a table (plan, winner, length, kills/losses, shots AI vs. player, metal, mines), what
decided the match, build errors or gave-ups worth fixing, what training changed (if run), an honest note that one
match can be chance, and exactly one concrete next step as a question.
