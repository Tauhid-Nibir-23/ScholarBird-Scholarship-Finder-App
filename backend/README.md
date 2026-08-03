# ScholarBird Backend — Generic Scraper Engine

This directory hosts a **standalone Python backend** that, in later phases,
automates scholarship collection for the existing ScholarBird Flutter +
Firebase mobile app.

> **Current phase is the Generic Scraper Engine.** A single concrete scraper
> (`DaadScraper`) is implemented as a reference. All reusable infrastructure
> — HTTP client lifecycle, retry, throttling, logging, error handling,
> normalization hooks — lives in `BaseScraper`. New scrapers only need to
> implement `fetch()` and `parse()`.

---

## Architecture

```
+-----------------------------------------------------------+
|                      Entry Points                         |
|  main.py  |  test_daad.py  |  scrapers/daad.py  |         |
|  run_scraper.py  |  tests/test_runner.py                   |
+-----------------------------------------------------------+
                          |
                          v
+-----------------------------------------------------------+
|              Generic Scraper Engine                       |
|       scrapers/base_scraper.py  (BaseScraper)             |
|   - httpx.Client lifecycle  - retry / throttling          |
|   - logging hooks           - error normalisation         |
|   - safe_get / sleep / build_headers / request            |
+-----------------------------------------------------------+
        |                       |                       |
        v                       v                       v
+----------------+    +------------------+    +-------------------+
| DaadScraper    |    | (future scrapers)|    | parser/           |
| (concrete)     |    | (Chevening, etc.)|    | normalize/        |
| fetch+parse    |    |                  |    | validate/dedupe   |
+----------------+    +------------------+    +-------------------+
        |                       |                       |
        +-----------+-----------+                       |
                    v                                   v
+-----------------------------------------------------------+
|                         Models                             |
|         models/scholarship.py  (Scholarship dataclass)    |
|       to_dict / from_dict / validate / to_firestore       |
+-----------------------------------------------------------+
                          |
                          v
+-----------------------------------------------------------+
|                  Cross-cutting Concerns                   |
|        core/logger.py | core/exceptions.py | core/retry.py |
|        core/helpers.py                                       |
+-----------------------------------------------------------+
                          |
                          v
+-----------------------------------------------------------+
|                       Config Layer                        |
|     config/settings.py  - env-driven, cached loader        |
|     config/constants.py - Firestore names, fields          |
+-----------------------------------------------------------+
                          |
                          v
+-----------------------------------------------------------+
|                       Firebase (later)                     |
|        firebase/firebase_config.py  - Phase 2 wiring       |
+-----------------------------------------------------------+
```

The arrows show **runtime dependency direction**: entry points depend on the
engine, the engine depends on `models/`, all layers depend on `core/` and
`config/`. Nothing depends upward.

---

## Layout

```
backend/
|-- config/                # Settings loader + project-wide constants
|   |-- __init__.py
|   |-- settings.py        # Cached env-driven settings
|   `-- constants.py       # Firestore collection + field names
|
|-- core/                  # Cross-cutting infrastructure
|   |-- __init__.py        # Public re-exports
|   |-- exceptions.py      # Typed exception hierarchy
|   |-- logger.py          # Rotating file + console logger
|   |-- retry.py           # @retry decorator with backoff
|   `-- helpers.py         # Small utilities
|
|-- models/                # Pure dataclasses
|   |-- __init__.py
|   `-- scholarship.py     # Scholarship value object
|
|-- scrapers/              # Generic Scraper Engine + concrete impls
|   |-- __init__.py
|   |-- base_scraper.py    # BaseScraper (engine)
|   `-- daad.py            # DaadScraper (concrete)
|
|-- parser/                # Normalise / validate / deduplicate (placeholders)
|   |-- __init__.py
|   |-- normalize.py
|   |-- validator.py
|   `-- duplicate.py
|
|-- firebase/              # Firebase placeholder - Phase 2 wiring
|   |-- __init__.py
|   `-- firebase_config.py
|
|-- tests/                 # Test harness (Phase 5: pytest)
|   |-- __init__.py
|   `-- test_runner.py     # Smoke test: discovery + validate + preview
|
|-- logs/                  # Rotating log files (gitignored)
|   |-- backend.log        # All records, level INFO+
|   |-- scraper.log        # Only backend.scrapers.* records
|   `-- errors.log         # ERROR+ from any module
|
|-- main.py                # Foundation banner
|-- test_daad.py           # Single-scraper smoke test (legacy entry)
|-- run_scraper.py         # Generic Runner CLI
|-- pyproject.toml
|-- requirements.txt
|-- .env.example
`-- .gitignore
```

---

## What Lives Where

| Folder      | Responsibility                                                              |
|-------------|-----------------------------------------------------------------------------|
| `config/`   | Read environment variables, expose static project-wide constants.            |
| `core/`     | Cross-cutting concerns: logging, exceptions, retry, helpers. No domain code. |
| `models/`   | Pure dataclasses. No I/O. `Scholarship.to_dict` / `from_dict` / `validate`.  |
| `scrapers/` | `BaseScraper` engine + concrete site scrapers (`DaadScraper`).               |
| `parser/`   | Reserved for normalisation, validation, deduplication logic (later phases).  |
| `firebase/` | Reserved for Firebase Admin bootstrap and Firestore writers (later phases).  |
| `tests/`    | Smoke test harness. Real pytest suite arrives in a later phase.              |
| `logs/`     | Output of the rotating log handlers. Created at runtime if missing.         |

---

## Design Rules

- **Python 3.11+**, PEP 8, full type hints on every public symbol.
- **`@dataclass(frozen=True)`** for value objects (`Scholarship`).
- **Google-style docstrings** on every public symbol.
- **No `print()`** outside `main.py` — use `get_logger(__name__)`.
- **No hacks.** If you need to run a script two ways (`python -m` and `python
  file.py`), solve it with a clean `sys.path` bootstrap at the top of the entry
  point. Do not duplicate library code.
- **Reuse everything.** HTTP plumbing, retries, throttling, logging hooks, and
  error normalisation all live in `BaseScraper`. Subclasses only override
  `fetch()` and `parse()`.
- **No global mutable state.** Settings are loaded via a single cached function
  (`get_settings()`).

---

## How to Run

The backend can be driven from several entry points. Pick the one that fits
your intent.

### 1. Foundation banner

```bash
python backend/main.py
```

Prints the foundation banner and exits. Useful for sanity-checking the
package layout and logger bootstrap.

### 2. DAAD scraper — legacy single-scraper smoke test

```bash
python backend/test_daad.py
```

Fetches the DAAD stipend database, parses records, validates each record,
prints a 5-row preview and a summary line. Exits non-zero on failure.

### 3. DAAD scraper — runnable module

Both forms work:

```bash
python -m backend.scrapers.daad
python backend/scrapers/daad.py
```

The `__main__` block uses the same `sys.path` bootstrap as `run_scraper.py`,
so the script is runnable from any working directory.

### 4. Generic Runner — CLI for all scrapers

```bash
# List every discoverable scraper
python backend/run_scraper.py --list

# Run one scraper, limited to 5 records
python backend/run_scraper.py --scraper daad --limit 5

# Run all scrapers (each capped at 50 records by default)
python backend/run_scraper.py --all
```

Discovery uses `pkgutil.iter_modules` over `backend.scrapers` and filters
out re-exports. Only concrete (non-abstract) subclasses of `BaseScraper`
appear in `--list`.

### 5. Smoke test harness

```bash
python backend/tests/test_runner.py
```

Runs every discovered scraper with a `--limit 5`, validates each record
with `Scholarship.validate(raise_on_error=True)`, round-trips
`to_dict` / `from_dict`, and prints a preview table. Exits non-zero if any
record fails validation.

---

## How to Create a New Scraper

The Generic Scraper Engine is designed so adding a new site is a small,
mechanical change.

1. **Create `backend/scrapers/<site>.py`.** The module name becomes the
   scraper's CLI name (`python backend/run_scraper.py --scraper <site>`).

2. **Subclass `BaseScraper`.** Set the `name` class attribute to a
   human-readable label (e.g. `"Chevening"`).

3. **Override exactly two methods:**
   - `fetch(self) -> Iterable[Any]` — perform the retrieval (one HTTP
     request, many HTTP requests, file read, whatever the site needs).
     Reuse `self._request()` for HTTP so retry/throttling/logging work
     automatically.
   - `parse(self, raw: Iterable[Any]) -> Iterable[Scholarship]` — turn
     raw payloads into `Scholarship` instances. Validate each one via
     `self._validate(scholarship)` if you want failures logged as warnings
     rather than raising.

4. **Do not duplicate infrastructure.** Don't write your own `httpx.Client`,
   retry loop, throttle, or logger. If you need a helper that isn't in
   `BaseScraper` yet, add it to the base and let every scraper benefit.

5. **Run it.** The new scraper appears in `python backend/run_scraper.py
   --list` automatically and can be invoked with `--scraper <site>`.

### Minimal example

```python
# backend/scrapers/example.py
from __future__ import annotations

from backend.core import get_scraper_logger
from backend.models import Scholarship
from backend.scrapers.base_scraper import BaseScraper


class ExampleScraper(BaseScraper):
    name = "ExampleSite"

    def fetch(self):
        # Reuse the engine's HTTP plumbing:
        response = self._request("GET", "https://example.com/data.json")
        return response.json()

    def parse(self, raw):
        for item in raw["results"]:
            yield Scholarship(
                title=item["title"],
                country=item["country"],
                degree=item["degree"],
                deadline=item["deadline"],
                link=item["url"],
                source=self.name,
            )
```

That's the entire surface area. Retry, throttling, error handling, logging,
and lifecycle management are inherited.

---

## Logging

Three rotating files are produced under `backend/logs/`:

| File           | Contents                                            |
|----------------|-----------------------------------------------------|
| `backend.log`  | All records at level `INFO`+ from every logger.     |
| `scraper.log`  | Only records from the `backend.scrapers.*` namespace. |
| `errors.log`   | Records at level `ERROR`+ from any module.          |

Rotation policy: **5 MB per file, 5 backups retained.** The policy is
configured by `LOG_MAX_BYTES` and `LOG_BACKUP_COUNT` in `core/logger.py` so
tests can shrink it.

Console output is also attached to the root logger at `INFO`. Use
`get_logger(__name__)` in your module to participate.

---

## Exceptions

The `core/exceptions` module exposes a typed hierarchy:

| Exception                | When it is raised                                      |
|--------------------------|--------------------------------------------------------|
| `ScholarBirdError`       | Root of the hierarchy. Catch this for any backend bug. |
| `ConfigurationError`     | Settings are missing or invalid at startup.            |
| `ScraperException`       | Any failure inside a scraper (fetch/parse/run).        |
| `NetworkException`       | HTTP failure after retry policy is exhausted.          |
| `RobotsDeniedException`  | The site explicitly refuses our request (403/robots).  |
| `ParsingException`       | The payload is unparseable in its current form.        |
| `ValidationError`        | A `Scholarship` failed validation.                     |
| `DuplicateError`         | A duplicate was detected during ingest.               |
| `FirebaseError`          | Firestore operation failed.                            |

`ScraperError` and `ParseError` are kept as legacy aliases so older call
sites keep working.

---

## What's Intentionally Out of Scope (later phases)

- Chevening / Erasmus / Fulbright scrapers (only `DaadScraper` ships today).
- APScheduler / cron / GitHub Actions wiring.
- Firebase Admin bootstrap and Firestore writes.
- Normalisation, deduplication, and AI enrichment.
- Monitoring, alerting, structured observability.

Those land in their own phases. The Generic Scraper Engine is the
foundation they will sit on.