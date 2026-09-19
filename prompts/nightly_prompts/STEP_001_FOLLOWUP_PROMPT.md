# STEP 005 — exact shared-metric identity in installed query-exporter 5.1.0

## Role and mode

You are performing one atomic archaeology task for a Python 3.12 SQL-to-scribbly exporter migration.

This task is strictly READ-ONLY. Do not modify, create, delete or format any file. Do not install packages, import or execute Python modules, start/stop/restart services, connect to databases, read YAML/DSN/config contents, access credentials, or use network resources.

Return the report in your response only. Do not write a report into the repository or server filesystem.

## Established context — do not re-investigate

- The failing Linux service invokes the installed distribution `query-exporter==5.1.0` under Python 3.12.
- Its source directory is:

  `/app/replfoz/fozbin/SQLPython/venv/lib/python3.12/site-packages/query_exporter`

- The project generator emits one global `metrics` mapping keyed by `metric_name`; each query contains a list of metric-name references.
- Project metadata contains a real collision topology: in ASH6/DAILYRES the names `delay_read`, `delay_write`, `r`, and `w` are each referenced by six different io queries in the same target.
- This step must determine only the legacy runtime identity/ownership semantics of such a shared name. It must not propose a replacement or fix.

Expected SHA-256 guards for installed source:

- `config.py`: `0b299778488d4b71e9cba6282f19882605f321020672f0923540f8f0176d814a`
- `executor.py`: `adebfa891b544aed5efb118ba07210e318f18b772a8a07de97deb867d346baa99`
- `main.py`: `6e134c325a47b83033cb9ec21eb56b3a8113a7ae77088013e3dccda30b02c17d`
- `metrics.py`: `68b496e11a67c4e2ca1e6b36b2ef5ec58977f869cc5faf344987e928a3e5c588`
- `schema.py`: `d11e3079690140efd7b6817d8a0b82c839bb706d924ec0b4002a81abfbdb9c17`

## Single goal

Trace, from parsed configuration to scribbly collector/series update, what happens when several query definitions reference the same metric name.

The report must answer with source evidence:

1. What object represents a configured metric definition, and what key identifies it?
2. How does a query resolve each name in its `metrics` list?
3. At what point is a scribbly collector or metric family created/registered, and what is its registry key/name?
4. Does query name, database name or another implicit value become a scribbly label or part of series identity?
5. If six queries reference `delay_read`, do they update one shared collector/series, create distinct labelled series, attempt duplicate registration, overwrite one another, or fail validation/startup?
6. Which code path performs the update and what exact key/labels are used there?

## Allowed source scope

Read only these installed files:

- `config.py`
- `schema.py`
- `metrics.py`
- `executor.py`
- `main.py` only if required to show construction/wiring of the above objects

You may read distribution metadata only to confirm version 5.1.0. Do not read `db.py`, `yaml.py`, actual configuration, DSN files, logs, SQL, tests outside the installed package, or unrelated packages.

## Mandatory procedure

1. Compute SHA-256 for the five files listed above before reading them.
2. Compare each hash with the expected value.
3. If any hash differs, STOP and report `BLOCKED: source fingerprint mismatch`, showing only filename, expected hash and actual hash. Do not continue analysis.
4. If hashes match, print numbered, contiguous source excerpts sufficient to prove each transition in the trace. Include file path and original line numbers. Do not replace decisive code with paraphrase or ellipses.
5. Build one explicit trace using the concrete example `delay_read` referenced by two hypothetical queries Q1 and Q2, applying only behavior proven by the exact code.

## Exclusions

Do not analyze in this step:

- multiple SQL result rows;
- NULL, strings, missing columns or invalid numeric values;
- counter accumulation correctness;
- scheduler intervals, first run, concurrency or stale-value retention;
- reconnect, transaction, timeout or DB failure behavior;
- HTTP routes, health endpoints or shutdown;
- current startup failure or ways to restore `sqlalchemy_aio`;
- replacement design, dependencies or implementation.

If one excluded topic appears in a cited function, quote only the minimum lines needed for shared-name identity and mark the excluded behavior `NOT ANALYZED`.

## Required report format

### 1. STATUS

`COMPLETE` or `BLOCKED`, with one sentence.

### 2. SOURCE IDENTITY

- distribution/version evidence;
- filename -> actual SHA-256 for the five guarded files;
- confirmation that all guards match.

### 3. EVIDENCE EXCERPTS

Numbered excerpts with absolute file path and original line range, covering:

- metric config/model key;
- query-to-metric reference resolution;
- collector/family construction and registration;
- update path and labels/identity.

### 4. SHARED-NAME TRACE

Step-by-step trace for Q1 and Q2 both referencing `delay_read`. State the exact resulting collector/series relationship. Separate observed code from inference.

### 5. ANSWERS

A compact table answering the six goal questions. Every answer cites an excerpt number. Use `UNKNOWN` if exact code in allowed scope is insufficient.

### 6. CONCLUSION

Choose exactly one, then justify it from excerpts:

- `ONE SHARED UNLABELLED SERIES`
- `ONE COLLECTOR WITH DISTINCT LABELLED SERIES`
- `DISTINCT COLLECTORS`
- `CONFIG/REGISTRATION FAILURE`
- `AMBIGUOUS — FOLLOW-UP REQUIRED`

Do not invent a category if the code does not decide it; use the ambiguous option and name the single smallest missing source artifact.

### 7. COMMANDS AND NO-CHANGE STATEMENT

List all commands executed. Confirm no files, services, packages, configs, databases or network resources were changed/accessed beyond the allowed source reads and version metadata.

## Acceptance criteria

- The exact installed 5.1.0 source is fingerprint-verified before analysis.
- The report proves shared-name identity from config lookup through update/collector registration.
- Implicit query/database labels are either evidenced or explicitly shown absent on that path.
- The concrete repeated-name example is resolved or one precise blocker is named.
- No behavior outside the atomic scope is analyzed and no writes/actions occur.
