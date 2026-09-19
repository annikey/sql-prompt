# STEP 003 — legacy query-exporter provenance in the repository

## CONTEXT

We are performing a compatibility-first migration of an old SQL-to-Prometheus exporter to Python 3.12. Do not design or implement the replacement yet.

Accepted facts relevant to this task:

- `scripts/query-exporter.py` is expected to be a thin wrapper importing `query_exporter.main.script`.
- The runtime currently fails under Python 3.12 because legacy code imports `ASYNCIO_STRATEGY` from `sqlalchemy_aio`.
- The generator and metadata contract are already investigated. Do not repeat that work.
- Repository metadata contains the same metric names (`delay_read`, `delay_write`, `r`, `w`) in several queries. Exact legacy runtime implementation is therefore needed before interpreting series identity or overwrite behavior.
- The last accepted source revision was `dc87828d1dfaddcd9ee68e712468ad59ea97d8ce` on branch `FOSQL-12128`. Record the actual revision at the start; do not assume it is unchanged.

## GOAL

Determine the exact provenance of the legacy `query_exporter` runtime that can be established from this repository alone: wrapper entry point, declared or pinned distribution/version, packaging/build references, and whether matching runtime source or an installable artifact is present in the repository.

This task identifies the implementation. It does not analyze its behavior.

## SCOPE

READ-ONLY. DO NOT MODIFY ANY FILES.

You may inspect only:

- `scripts/query-exporter.py` and directly adjacent runtime/package metadata such as `meta.info` if present in the repository;
- dependency declarations and lock/manifests used by this project (`requirements*`, constraints, setup/pyproject/Pipfile/poetry files, Gradle dependency/package lists, environment/bootstrap scripts);
- `build.gradle` only where it refers to Python runtime dependencies, the wrapper, virtualenv, or packaging of query-exporter;
- repository files or archives whose names/content directly indicate `query_exporter`, `query-exporter`, `sqlalchemy_aio`, `SQLAlchemy`, `pyodbc`, `prometheus_client`, or a Python distribution/version;
- Git metadata needed to report revision and worktree state.

Use a narrow filename/content search to locate these items. A repository-wide textual search for the exact identifiers above is allowed; do not perform a general architecture survey.

## DO NOT

- Do not modify, format, generate, delete, stash, reset, commit, or create files.
- Do not write the report into the repository; return it only in the response.
- Do not use network access or web search.
- Do not install, upgrade, uninstall, import, or execute Python packages.
- Do not activate or inspect a server virtualenv outside the repository.
- Do not run Gradle, project scripts, SQL, tests, services, containers, or deployment commands.
- Do not open YAML/DSN files containing credentials and do not print secrets.
- Do not analyze metric mapping, scheduling, HTTP behavior, DB failure handling, or propose replacement architecture.
- Do not assume that an unpinned package equals any current upstream release.
- Do not treat a package filename, comment, or `meta.info` value as authoritative without explaining how it is connected to the packaged runtime.
- Do not investigate generator logic or metadata values again.

## EXPECTED OUTPUT

Return one Markdown report in the response with these sections:

1. `STATUS`: `COMPLETE`, `PARTIAL`, or `BLOCKED`.
2. `REVISION AND WORKTREE`:
   - full `git rev-parse HEAD`;
   - branch;
   - short status before and after;
   - statement that no files were changed by this task.
3. `ENTRY POINT`:
   - exact path and complete numbered content of the thin wrapper;
   - any repository evidence showing how that wrapper is packaged or invoked, with narrow path/line citations.
4. `DEPENDENCY PROVENANCE` table with columns:
   - `evidence path:lines`;
   - `declared name`;
   - `version/constraint exactly as written`;
   - `role or connection to runtime`;
   - `strength`: exact pin / range / unpinned / comment / artifact metadata.
   Include `query-exporter`/`query_exporter`, `sqlalchemy-aio`/`sqlalchemy_aio`, SQLAlchemy, pyodbc, PyYAML and prometheus client only when evidence is actually present.
5. `SOURCE OR ARTIFACT AVAILABILITY`:
   - list any vendored package directory, wheel, sdist, archive, lock cache, or copied source that could establish the legacy implementation;
   - for each, give exact path, artifact filename/version evidence and whether its contents were inspected;
   - if none exists, state the bounded paths/patterns searched. Do not claim absence outside that boundary.
6. `CONCLUSION`:
   - strongest exact runtime identity justified by repository evidence;
   - whether repository evidence is sufficient to inspect legacy behavior in the next read-only step;
   - if insufficient, list the minimal server-side facts needed later, such as sanitized output of distribution metadata and filesystem path to installed package source. Do not provide or run those commands in this task.
7. `COMMANDS`: exact read-only commands run.
8. `UNRESOLVED`: contradictions, ambiguous pins, generated files absent from Git, or missing provenance links.

Keep excerpts narrow. Never include credentials, DSN contents, connection strings, or unrelated configuration.

## ACCEPTANCE CRITERIA

- Every claimed version or dependency relation is backed by a path and line range or by an identified artifact name/metadata record.
- The wrapper's exact import and invocation are shown completely.
- The report distinguishes exact pin, compatible range, unpinned declaration, transitive inference, and artifact metadata.
- It establishes whether matching legacy source/artifact is locally available, or gives a bounded negative result.
- It does not interpret runtime metric behavior or recommend implementation.
- Worktree state is unchanged by this task.

## STOP CONDITIONS

Stop without expanding scope if:

- repository access or Git metadata is unavailable;
- the relevant dependency data is encrypted, credential-bearing, generated only on a server, or outside the repository;
- multiple conflicting versions are found and their packaging path cannot be resolved from the allowed files;
- determining the installed version would require running/importing the broken environment, accessing a server, installing packages, or using the network.

In that case, return `PARTIAL` or `BLOCKED`, cite what was found, and identify the single smallest missing artifact. Do not guess.

## COMMANDS / VALIDATION

Use read-only commands such as:

```bash
git rev-parse HEAD
git branch --show-current
git --no-optional-locks status --short --untracked-files=normal
find . -type f \( -iname 'requirements*' -o -iname '*constraints*' -o -iname 'pyproject.toml' -o -iname 'setup.py' -o -iname 'setup.cfg' -o -iname 'Pipfile*' -o -iname 'poetry.lock' -o -iname '*query*exporter*' -o -iname '*meta.info*' -o -iname '*.whl' -o -iname '*.tar.gz' -o -iname '*.zip' \) -print
grep -RIn --exclude-dir=.git -E 'query[-_]exporter|sqlalchemy[-_]aio|SQLAlchemy|pyodbc|prometheus[_-]client|PyYAML' <narrow paths found above>
nl -ba <relevant file>
```

If `rg` is available, it may replace `find`/`grep`. Do not run a command that reads generated secrets or dependency caches outside the repository. Repeat `git status` at the end and compare it with the initial output.
