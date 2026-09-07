# Agent Instructions

## Project Rules

- SwiftLint `--strict` is a build gate: warnings are errors; the `no_comments`
  custom rule stays at error severity. It covers `Sources`, `Tests` and `src/ios`.
- Every feature lands with unit tests, and integration tests for new flows.
- Integration tests run against local, in-process fixtures and servers — never
  against real remote servers or the public internet.
- Every Swift and C source file under `Sources/` and `src/ios/` is listed in
  `plugin.xml`. `Tests/NetworkDiagnosticsTests/PluginManifestTests.swift`
  enforces that parity, unique file basenames, and agreement between the
  registered Objective-C class name, the Swift `@objc(...)` name, the native
  type string and the JavaScript `_nativeType`.
- `src/ios/` is bridge glue only: it parses parameters, starts work and
  delivers results on the main thread. Logic, parameter validation and JSON
  encoding live in `Sources/NetworkDiagnostics/` and are unit-tested there.
  Files under `src/ios/` are compiled only by the Cordova build.
- The JavaScript API in `www/` and the `state`-discriminated result shapes it
  returns are public contracts. A change is a coordinated edit of `www/`,
  `Sources/NetworkDiagnostics/Bridge/`, their tests and `README.md`.
- Verification runs on the iOS Simulator through `scripts/`. The global
  physical-iPad deployment rule does not apply to this repository.
- Commit messages never name the agent instructions file; a pre-commit hook
  rejects messages that contain that word.

## Where Things Live

- Tabris.js plugin mechanics (bridge operations, properties, methods, events,
  data marshalling, widgets, console): `docs/knowledge/tabris-ios-plugins/`,
  start at `_index.md`.
- Decisions: `docs/decisions/`. Vocabulary and forbidden synonyms:
  `docs/glossary.md`.
- Library: `Sources/NetworkDiagnostics/` (Swift package, `Package.swift`);
  resolver C shim: `Sources/CResolv/`.
- Bridge: `src/ios/`; JavaScript module: `www/`; Cordova manifest:
  `plugin.xml`.
- Example app: `example/` (`example/build.sh`); simulator drivers: `scripts/`.
- Tests: `Tests/`. `swift test` on the macOS host is the fast loop;
  `scripts/run-simulator-tests.sh` on a dedicated simulator is the gate.

## Guiding Principles

1. **Uncertainty must not be hidden.** When the system is uncertain about a result,
   it must surface that uncertainty to the user rather than guessing silently.
   A visible "unsure" is better than a confident mistake.

2. **Long-running operations show progress.** The user must see incremental progress
   while work is in flight — never a frozen or empty screen until completion.
   Partial output that gets corrected later is acceptable; a silent UI during an
   active operation is a bug. This applies equally to test/mock modes.

## Engineering Principles

- **No dead code or backward-compat shims.** Remove immediately; don't leave for
  "later cleanup."
- **No premature abstraction.** Do not add configuration parameters, indirection
  layers, or aliases to support hypothetical future use cases. Simplify now; do not
  build for hypotheticals. If a real second use case appears later, refactor then.
- **Rule of Three (DRY with a threshold).** Duplicating code twice is acceptable;
  extract an abstraction on the third occurrence. The wrong abstraction is worse
  than duplication — when in doubt, duplicate.
- **SLAP — one level of abstraction per function.** A function body should read like
  a table of contents. If it needs `// 1. …` step markers, extract named private
  functions instead. Enforce mechanically via linter complexity/length thresholds.
- **Make illegal states unrepresentable.** Model state and uncertainty as enums /
  sum types with associated values, never as co-varying `Bool`/`String` fields that
  can disagree. This is the type-level extension of "uncertainty must not be hidden."
- **Functional core, imperative shell.** Algorithms are pure functions with no
  service/model/I-O dependencies; services are the thin shell that owns I/O and
  external resources. A pure core is testable without fixtures.
- **No lazy loading / autoload of heavy resources.** Loading a heavy resource
  (model, large file, connection pool) must be explicit — triggered by user action
  or a startup sequence, never by first use.
- **Separate debug, UI, and business logic.** Avoid god-classes. Gate diagnostic
  output behind debug builds. Error-level logging for rare failures is acceptable
  in production.
- **No silent failures — full error handling, always.**
  - A failure that prevents using the app must surface in the UI via a visible
    failed state, not disappear into a log.
  - Any other unexpected failure must at least emit an error-level log entry.
  - Never swallow an error with an ignored result, an empty catch, or a bare
    guard-return without logging.
  - Error messages must carry enough concrete context — what operation failed,
    in which component, and the underlying reason — that the user understands what
    happened and can report it to developers actionably. "Something went wrong"
    is a bug, not an error message.
- **Use a logging facade, not raw print.** Debug level for diagnostics (not
  persisted), info level for lifecycle events, error level for failures (always
  persisted). Development tooling sees all levels.
- **Public interfaces are contracts — they never break.** New fields are optional
  additions. Breaking the contract means changing every implementation; treat that
  as a deliberate, coordinated migration, never a casual edit.
- **One concept, one identifier — no aliases.** A component's registry name, its
  emitted event names, and the resource it owns must share the same identifier.
  No hardcoded names diverging from registry keys. A second backend for the same
  role gets a parallel component, not a backend-selector parameter on one component.
- **Generic code stays generic in prose, too.** Code designed to work with any
  configured backend must use only abstract terms in its identifiers and docs —
  never a concrete vendor/model name as a stand-in. A concrete name in a generic
  context silently re-couples the abstraction to one backend and misleads the next
  person configuring a different one. Concrete names belong only in backend-specific
  files, where the type name already scopes them.
- **Fixture-first testing.** Every component can be tested with recorded fixtures
  instead of live resources. Provide a way to capture real outputs as fixtures and
  to inject fixtures in place of live dependencies.
- **Test modes are primary paths.** Behaviour in mocked/replay mode must match
  production mode — bugs that reproduce only in mock mode are still bugs.
- **Measure before architecting.** Do not propose replacing a working design on
  speculative grounds. The decision flow is: implement the candidate → run the
  benchmark → compare recorded results → decide. Roadmaps that assume a winner
  before the measurement are out of scope.
- **Artefact names encode the exact variant.** Filenames for benchmark reports,
  fixtures, and result rows must make the measured variant fully identifiable
  (version, size, configuration). Generic names are ambiguous and will be renamed.
- **Track results in committed, diffable form.** Every benchmark/eval run appends
  to versioned result files so the trend is visible in review diffs.
- **Plans that add a variant end with a measurement step.** When a plan introduces
  a new component, parameter, or backend, the final mandatory step runs the full
  comparison across relevant combinations and records the results. Preceding steps
  are wiring + smoke tests only; the measurement is the validation gate.
- **One person, one module.** Work on a single module at a time. Don't modify other
  modules' code. Interfaces are the contract.
- **All entry points share the same core interfaces.** CLI, app, and test harness
  exercise identical core code paths — no per-frontend forks of the logic. Here:
  the all-in-one run and the individual primitives share `HostProbes` and the
  same services.

## Naming Discipline

- **One concept, one name** — in types, identifiers, and docs. Maintain a project
  glossary mapping each domain term to its meaning and explicitly listing forbidden
  synonyms. Do not introduce synonyms.
- **Unit suffixes are mandatory** on numeric identifiers whose unit is not carried
  by the type: `…Seconds` for time, `…Bytes` for sizes, `…Samples` for counts
  (e.g. `windowSamples`, not `windowSize`). Fields whose type carries the unit may
  keep plain names — but never mix two naming conventions for the same pair of
  concepts within new code; pick one and state it in the glossary. JavaScript
  result keys follow the same suffix rule (`latencyMs`, `durationSeconds`).

## UI Language Consistency

- User-facing UI ships in exactly one language, written directly in code. The
  failure mode to prevent is a stray fragment of another language reaching the
  user through inattention. Do not pre-localize or add localization plumbing for
  hypothetical future languages.
- Debug-only surfaces stay in the team's working language — they are internal
  tooling.
- Everything else (CLI output, source code, comments where permitted, docs, commit
  messages) stays in the team's working language.

## Code and Documentation Hygiene (The "What Goes Where" Rule)

Rigorously manage where system knowledge is stored. **Never dump all context into
a single place.** Distribute knowledge according to the following rules:

1. **Commit Message:**
   - **What:** Describes the change and its scope (imperative mood for the title).
   - **Why:** Brief justification (max 1-2 sentences).
   - **Links:** References to decision records or issue-tracker numbers.
   - *Forbidden:* Stack traces, architectural essays, and long logs.

2. **Production code — no comments at all:**
   - Production sources contain zero comments — no doc comments, no inline
     comments, no section markers. Intent is carried by names, types, and function
     decomposition. Enforce with a linter rule at error severity.
   - **Permitted exceptions:** linter directives (written without an added
     justification — that belongs in the commit message), and comment syntax
     inside string literals that a downstream consumer actually reads.
   - **Where the knowledge goes instead:** an API contract the signature cannot
     express, and any rationale, go to a decision record; what changed and why
     goes to the commit message; a constraint that breaks when violated gets a
     test or a compile-time constraint, never a comment.
   - **Test targets and third-party wrapper layers keep their comments.** Tests
     state what a failure means; wrappers track upstream API semantics the local
     signatures do not carry. The C shim, the bridging header, `plugin.xml` and
     the JavaScript module count as wrapper layers.

3. **Architecture Decision Records (ADR) — `docs/decisions/`:**
   - **What:** Full motivation, broader context, technical constraints, and
     rejected alternatives.
   - **How:** Separate Markdown files: `docs/decisions/YYYY-MM-DDThhmmZ-short-description.md`.
   - The ADR must focus on the decision and be included in the same commit as the
     related code changes. The commit message must link to it.

## CLAUDE.md Discipline

- **CLAUDE.md captures invariants and rules — not current state.** Specific version
  pins, current defaults, lists of active backends — none of these belong in
  CLAUDE.md. They live in source (registries, manifests, config files) and can be
  checked at zero cost. What belongs in CLAUDE.md instead: architectural rules,
  naming conventions, location pointers to where current state actually lives, and
  the *kinds* of things the stack uses. Heuristic: if a line would start with
  "currently …" or "default is <specific version>" — rewrite it to point at the
  registry instead.

## Before Committing

- Run the linter, the host test suite (`swift test`), `bash -n` on every shell
  script and `node --check` on every JavaScript file touched by the commit.
- Verify the "What Goes Where" rules are respected and that complex decisions
  have been extracted to decision records.
