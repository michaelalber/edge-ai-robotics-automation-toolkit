# [PROJECT NAME] — Evals
<!-- Discipline 4: Specification Engineering — Primitive 5: Evaluation Design
     Framework: Four Prompt Disciplines & Five Primitives (Nate B. Jones, v2026.03.2)

     PURPOSE: Safety infrastructure. The eval is the only thing standing between
     an agent that is technically capable and one that is organizationally safe.

     KEY RULES:
     - Write evals BEFORE the agent starts, not after it finishes.
     - An agent without evals does not know what it doesn't know about your context.
     - Run evals after every significant model update or prompt change.
     - In dark factory architecture, the agent CANNOT declare done without passing evals.
     - Eval design requires senior judgment, not junior execution.

     Copy this template to your project root. Fill in test cases for each
     recurring task type. Delete placeholder comments before committing. -->

---

## Eval Philosophy

Evals are not a finishing step — they are **safety infrastructure**. Write them before the
agent starts. Run them after every model update. A passing test suite ≠ done; tests verify
code correctness, evals verify output is actually good relative to project intent.

A passing eval is measurable, repeatable, and would survive scrutiny from
[KEY STAKEHOLDER — e.g., the lead engineer, the product owner, the client].

Evals answer: *"Is the output actually good?"* — not *"does it look reasonable?"*

---

## Test Cases

<!-- 3–5 test cases per recurring task type with known-good reference outputs.
     Run after every significant model update or prompt change.
     Catching regression early is the whole point. -->

### Test Case 1: [Task Type — e.g., Feature Implementation]

- **Input / Prompt:** [The exact input or Jira issue used]
- **Known-Good Output:** [What a correct, high-quality response looks like — be specific]
- **Pass Criteria:**
  - [ ] [Specific, binary check — e.g., "All tests pass with `dotnet test`"]
  - [ ] [e.g., "No new compiler warnings introduced"]
  - [ ] [e.g., "Follows vertical slice architecture: no cross-feature dependencies"]
- **Last Run:** YYYY-MM-DD | **Result:** [Pass / Fail / Partial]
- **Notes:** [Any drift or regression observed]

---

### Test Case 2: [Task Type — e.g., Code Review]

- **Input / Prompt:**
- **Known-Good Output:**
- **Pass Criteria:**
  - [ ]
  - [ ]
- **Last Run:** | **Result:**
- **Notes:**

---

### Test Case 3: [Task Type — e.g., Documentation / Confluence page]

- **Input / Prompt:**
- **Known-Good Output:**
- **Pass Criteria:**
  - [ ]
  - [ ]
- **Last Run:** | **Result:**
- **Notes:**

---

## Taste Rules (Encoded Rejections)

<!-- Each entry = a lesson from a rejected output.
     Format: Pattern → Why it fails → Rule going forward.
     Review weekly. Add new rules as you reject outputs.
     This is your institutional taste, made explicit and persistent.
     "An agent without evals does not know what it doesn't know about your context." -->

| # | Pattern to Reject | Why It Fails | Rule |
|---|---|---|---|
| 1 | Output that "looks right" but isn't grounded in project context | Generic output wastes time — requires cleanup that defeats delegation | Always anchor recommendations to a specific fact from AGENTS.md or the active Jira spec |
| 2 | Nullable column on main entity for optional grouped data (e.g., `Address?` columns on `Customer`) | Should be owned entity on separate table; nullable columns introduce 3VL into the principal query | For any optional multi-field concept, default to `OwnsOne(..., pb => pb.ToTable(...))` |
| 3 | Enum-like states encoded as `bool?` or `string?` (e.g., `IsApproved?`) | Bool/string nullable flattens multiple states into ambiguous NULL; broke filter queries in prod | Use an explicit enum property with a named `NotApplicable` or `Pending` variant instead |
| 4 | [Pattern] | [Why it fails] | [Rule going forward] |

---

## CI Gate

<!-- The CI pipeline result is a first-class eval input for software projects.
     A passing test suite ≠ done — it is necessary but not sufficient.
     The agent must not declare a task complete if any gate below fails.
     Update these entries to match the actual commands in this project. -->

- **Build:** `[e.g., dotnet build / npm run build]` — zero errors, zero warnings
- **Tests:** `[e.g., dotnet test / pytest / npm test]` — all pass
- **Coverage:** ≥ [80]% — run `[test command with coverage flag]`
- **Security scan:** `snyk code test` — zero high or critical issues
- **Lint / static analysis:** `[e.g., dotnet build -warnaserror / ruff check / eslint]` — clean

> Append CI gate results as a sub-item of each Test Case entry on every run.

---

## Rejection Log

<!-- Running log of rejected outputs. Review weekly to extract new Taste Rules above.
     Never delete entries — they are the institutional memory of what "wrong" looks like.
     Memory hygiene: prune the Taste Rules table when a rule is superseded, not here. -->

### YYYY-MM-DD — [Task Description]

- **What was generated:** [Brief description]
- **What was wrong:** [Recognition — what tipped you off?]
- **Why it was wrong:** [Articulation — root cause]
- **Rule extracted:** [Encoding — add to Taste Rules above if recurring]
