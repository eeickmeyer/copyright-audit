# Code Outline

`copyright-audit` is a single-file hybrid Bash + Python script (~4 620 lines).
The Bash wrapper handles argument parsing, scanner invocation, and environment
setup; the embedded Python (via heredoc) does all analysis, reporting, and
interactive fixing.

---

## Bash Wrapper (lines 1–250)

| Lines | Section | Purpose |
|-------|---------|---------|
| 1–50 | Header / help text | GPL-3 license header, usage documentation |
| 52–95 | Argument parsing | `while` loop over `$@`; sets `MODE`, `EXCLUDE_PATTERNS`, `OUTPUT`, `VERBOSE`, `FIX_MODE`, `YES_MODE`, `NO_FETCH`, `JOBS`, `SRCDIR` |
| 97–109 | Source-dir resolution | Resolves `SRCDIR` to absolute path; validates `debian/copyright` exists (check/review modes) |
| 111–128 | Scanner detection | Prefers `scancode` → `licensecheck`; requires `python3` |
| 130–156 | Temp dir & exclusions | Creates `$_WORKDIR`; builds default exclude list (VCS, build artifacts, copyright file itself) |
| 158–213 | Run scanner | Invokes scancode (JSON output) or licensecheck (deb-machine text); optionally runs cross-validation scans (licensecheck as sanity check, decopy) |
| 215–237 | Decopy-accelerated generation | If `generate` mode and `decopy` is installed, runs `decopy --quiet .` to seed the initial copyright file, then switches to `check` + `fix` + `yes` mode so the full hardening pipeline runs automatically |
| 239–268 | Pass state to Python | Exports everything as env vars; launches `python3 -` heredoc |

---

## Embedded Python (lines 269–4 623)

### Initialization & Configuration (lines 269–440)

| Lines | Section | Purpose |
|-------|---------|---------|
| 269–290 | Env-var intake | Reads all exported variables into Python globals (incl. `_decopy_generated` flag) |
| 292–299 | Native-package detection | `_is_native_package()` — reads `debian/source/format` |
| 282–300 | Built-in license texts | `_BUILTIN_LICENSE_TEXTS` dict (e.g. Unsplash license) |
| 302–403 | License text fetcher | `fetch_license_text()`, `_fetch_cc_text()`, `_fetch_spdx_text()`, `_fetch_url()`, `format_license_body()` — downloads from SPDX API / Creative Commons |
| 405–440 | Exclusion & metadata helpers | `is_excluded()`, `is_metadata_file()` — glob-matching utilities |

### License Normalization (lines 442–594)

| Lines | Section | Purpose |
|-------|---------|---------|
| 442–562 | `SPDX_TO_DEP5` | 130+ entry mapping dict from scanner output to DEP-5 names |
| 563–573 | `to_dep5()` | Normalize any license ID to DEP-5 convention |
| 575–581 | `SOURCE_EXTS` | Set of recognized source-code file extensions |
| 583–594 | `norm_cmp()` | Normalize for comparison only (collapses aliases, strips versions) |

### Scan Result Parsing (lines 596–726)

| Lines | Section | Purpose |
|-------|---------|---------|
| 596–667 | ScanCode JSON parser | Iterates `files[]`, extracts `license_detections` (with confidence filtering → `low_confidence` list) and `copyrights` |
| 669–715 | licensecheck parser | Parses `--deb-machine` paragraph output |
| 718–726 | `progress()` | Stderr progress bar for large scans |

### Metadata Enrichment (lines 728–940)

Overrides scanner heuristics with authoritative embedded metadata.

| Lines | Section | Purpose |
|-------|---------|---------|
| 730–743 | Path-to-result index | `_path_to_result` dict for O(1) enrichment lookups |
| 744–809 | KDE `metadata.json` | Extracts `KPlugin.Authors`, detects Unsplash URLs, applies to image files via symlink resolution |
| 811–899 | SVG RDF/XML metadata | Parses `<cc:license>` and `<dc:creator>` from SVG `<metadata>` — overrides scancode's CC version guesses |
| 901–940 | GNOME background XML | Parses `<wallpaper>` elements in `gnome-background-properties/*.xml`, extracts "by Artist" pattern |

### Directory License Inheritance (lines 943–1024)

| Lines | Section | Purpose |
|-------|---------|---------|
| 943–1003 | Inheritance logic | Files with no detected license inherit from directory's dominant license — only when a COPYING/LICENSE file exists nearby; skipped for native packages |

### Existing `debian/copyright` Parsing (lines 1026–1092)

| Lines | Section | Purpose |
|-------|---------|---------|
| 1026–1082 | Stanza parser | Populates `stanzas` (glob→license) and `stanza_copyrights` (glob→holders) |
| 1084–1092 | License block parser | Populates `license_blocks` (name→body text) for standalone License paragraphs |

### Validation Functions (lines 1097–1529)

These are pure functions called by both check and review modes.

| Lines | Function | Purpose |
|-------|----------|---------|
| 1097–1170 | `check_license_completeness()` | Verifies each referenced license has a text block; checks CC full-text, FIXME stubs, common-licenses refs |
| 1173–1209 | `check_coverage()` | Finds files uncovered by any stanza; finds stale globs matching no file |
| 1211–1303 | `check_license_compatibility()` | Detects known conflicts: Apache+GPL-2, GPL-2-only+GPL-3-only, CDDL+GPL, EPL+GPL, etc. |
| 1305–1465 | `check_dep5_format()` | Structural DEP-5 validation: Format header, field ordering, tabs, trailing whitespace, blank continuation lines, duplicate globs, catch-all stanza, etc. Returns `(line, severity, message, fix_tag)` tuples |
| 1467–1529 | `fix_dep5_format()` | Auto-applies DEP-5 format fixes (trailing whitespace, tabs, blank continuations, missing newline) |

> **Note on `SYSTEM_COMMON_LICENSES`** (line 1089): populated at import time
> from `/usr/share/common-licenses/` and used by both completeness and fix logic.

### Copyright Comparison Utilities (lines 1532–1952)

Includes corporate-suffix awareness (line 1551) to avoid splitting names
like "Rep Invariant Systems, Inc." on commas.

| Lines | Function | Purpose |
|-------|----------|---------|
| 1532–1550 | `get_declared_license()` / `get_declared_copyrights()` | DEP-5 last-match-wins lookup for a filepath |
| 1558–1592 | Email/Unicode helpers | `_deobfuscate_email()`, `_strip_email()`, `_extract_email()`, `_normalize_unicode()` |
| 1594–1636 | `norm_copyright()` / `_parse_copyright()` | Normalize copyright strings; split into (years, author) |
| 1638–1693 | `_split_multi_authors()` | Splits "A, B and C" into individual authors; handles corporate suffixes (Inc., Ltd., GmbH) |
| 1696–1733 | `_infer_years_from_paths()` | Fallback year detection via `git log` (batched) or file mtime |
| 1736–1897 | `merge_copyrights()` | Core deduplication engine: groups years by normalized author, email-based dedup, compressed-key dedup, fuzzy edit-distance dedup, Unicode preference, year-range collapsing |
| 1899–1952 | Formatting helpers | `format_files_field()`, `_copyright_continuations()`, `format_copyright_field()` |

### Copyright Holder Audit (lines 1954–2025)

| Lines | Function | Purpose |
|-------|----------|---------|
| 1954–2025 | `check_copyright_holders()` | Compares detected vs. declared holders per stanza; returns missing, extra, and per-file attribution maps |

### Stanza Consolidation (lines 2026–2207)

| Lines | Function | Purpose |
|-------|----------|---------|
| 2030–2077 | `_parse_paragraph_stanzas()` | Re-parses copyright text into structured stanza dicts |
| 2079–2131 | `check_consolidation()` | Groups stanzas by (license, holder-set); identifies merge candidates |
| 2134–2207 | `_simplify_file_list()` | Reduces file lists to dir/* globs; merges sibling globs with common prefixes |

### False-Positive Classification & Compatibility (lines 2209–2362)

| Lines | Function | Purpose |
|-------|----------|---------|
| 2212–2227 | `classify_fp()` | Classifies likely false-positive mismatches (autoconf boilerplate, LICENSE text files, build files, metadata) |
| 2229–2328 | `licenses_compatible()` | Full GPL/LGPL/AGPL/GFDL family subsumption, BSD/MIT aliases, LGPL→GPL conversion, MPL-2.0 exception |
| 2315–2344 | `_NONFREE_RAW` / `NONFREE` / `is_nonfree()` | Non-free/non-DFSG license detection (SSPL, BUSL, CC-NC, CC-ND, etc.) |
| 2349–2362 | `_warn_stubs()` | Post-write warning for unresolved FIXME/TODO/PLACEHOLDER tokens |

---

## Mode: generate (lines 2393–2740)

Builds a new `debian/copyright` from scan results. **When `decopy` is
installed**, the Bash wrapper runs decopy first to seed the file (lines
215–237), then switches to check+fix+yes mode — so the generate path below
is the fallback when decopy is absent.

| Lines | Section | Purpose |
|-------|---------|---------|
| 2393–2430 | File grouping | Collects per-file data; counts licenses to pick catch-all; groups by (license, author-set) |
| 2433–2495 | `smart_glob()` | Directory-aware glob generation with sibling merging |
| 2496–2560 | Catch-all + per-author stanzas | Emits `Files: *` then per-author stanzas |
| 2561–2620 | `debian/*` stanza proposal | Interactive prompt for packaging stanza (skipped for native packages) |
| 2622–2680 | License text blocks | Common-licenses references, SPDX/CC fetching, FIXME stubs for unfetched |
| 2682–2740 | Warnings & summary | Non-free detection, loud compatibility banner, file/stanza counts |

---

## Mode: check / review — Setup (lines 2743–2872)

| Lines | Section | Purpose |
|-------|---------|---------|
| 2743–2795 | Load auxiliary results | Parses decopy output and licensecheck sanity-check results |
| 2797–2837 | `run_sanity_check()` | Cross-validates scancode vs. licensecheck by license family |
| 2839–2872 | Classification loop | Iterates scan results; populates `real_mismatches`, `fp_mismatches`, `no_license`, `apache_files`, `all_scan_licenses` |

---

## Mode: review (lines 2873–3180)

Structured pass/fail report with 19 tests.

| Test | Lines | What it checks |
|------|-------|----------------|
| 1 | 2884 | DEP-5 format validation |
| 2 | 2902 | Catch-all `Files: *` stanza |
| 3 | 2907 | License mismatches |
| 4 | 2911 | Undeclared licenses |
| 5 | 2928 | License compatibility (loud `!`-banner on failure) |
| 6 | 2944 | Non-free licenses in source |
| 7 | 2954 | Source files without license headers |
| 8 | 2959 | License text completeness |
| 9 | 2974 | Stanza coverage (uncovered files) |
| 10 | 2989 | Stale stanza globs |
| 11 | 3002 | Copyright holder accuracy |
| 12 | 3018 | Decopy findings |
| 13 | 3026 | Low-confidence detections |
| 14 | 3034 | Stanza consolidation opportunities |
| 15 | 3050 | FIXME entries in copyright file |
| 16 | 3070 | Versionless / invalid license identifiers |
| 17 | 3086 | Broad glob override conflicts |
| 18 | 3115 | Duplicate file declarations |
| 19 | 3135 | Scanner cross-validation (scancode vs. licensecheck) |

Ends with verdict (lines 3155–3180).

---

## Mode: check — Standard Report (lines 3180–3650)

When entered via the decopy-accelerated generate path, stdout is redirected
to stderr (line 3186) so the check report doesn't pollute the copyright output.

| Section | Lines | Content |
|---------|-------|---------|
| 0 | 3197 | DEP-5 format validation |
| 1 | 3215 | License mismatches — needs review |
| 2 | 3248 | Likely false positives (informational) |
| 3 | 3269 | License text completeness |
| 4 | 3289 | License compatibility + non-free warnings (loud `!`-banner) |
| 5 | 3332 | All licenses found in source |
| 6 | 3343 | Stanza coverage analysis |
| 7 | 3396 | Files with no detected license |
| 8 | 3421 | Copyright holder accuracy |
| 9 | 3451 | Stanza consolidation |
| 10 | 3475 | Decopy findings |
| 11 | 3487 | Scanner cross-validation |
| 12 | 3506 | Low-confidence detections |
| Summary | 3518 | Aggregate counts, result verdict |

---

## Interactive Fix Mode (lines 3650–4608)

Entered via `--fix` flag, post-check prompt, or automatically when the
decopy-accelerated generate path is active.

| Fix | Lines | What it does |
|-----|-------|--------------|
| 0 | 3683 | Apply DEP-5 format fixes (whitespace, tabs, blank continuations) |
| 1 | 3701 | Add new `Files:` stanzas for mismatched files (per-author grouping) |
| 2 | 3833 | Remove stale globs that match no file |
| 3 | 3869 | Add missing standalone `License:` text blocks (common-licenses ref or SPDX fetch) |
| 4 | 3940 | Update copyright holders — adds missing holders; proposes new stanzas instead of polluting `Files: *` |
| 5 | 4236 | Propose `debian/*` packaging stanza (or add packager to existing one) |
| 6 | 4338 | Consolidate stanzas sharing same license + authors |
| 7 | 4435 | Normalize copyright lines (year ordering, email deobfuscation, brackets) |
| 8 | 4495 | Replace inline license text with `/usr/share/common-licenses/` references |
| — | 4576 | Write result: backup `.bak`, write changes, warn about remaining FIXME stubs |

After fix mode, if the decopy-accelerated generate path is active (lines
4609–4620), stdout is restored and the hardened file is emitted to stdout
(or confirmed at the `-o` path).

---

## Key Data Structures

| Variable | Type | Scope | Purpose |
|----------|------|-------|---------|
| `scan_results` | `list[dict]` | Global | `{"path", "licenses", "copyrights"}` per file |
| `low_confidence` | `list[tuple]` | Global | `(path, license, score)` for skipped detections |
| `stanzas` | `list[tuple]` | Global | `(glob, license_id)` from existing `debian/copyright` |
| `stanza_copyrights` | `dict` | Global | `{glob: [copyright_holders]}` |
| `license_blocks` | `dict` | Global | `{license_name: body_text}` standalone blocks |
| `SPDX_TO_DEP5` | `dict` | Const | 130+ scanner-output → DEP-5 name mappings |
| `_NONFREE_RAW` | `set` | Const | Non-free/non-DFSG license identifiers |
| `SOURCE_EXTS` | `set` | Const | Recognized source file extensions |
| `COMMON_LICENSES` | `set` | Const | Licenses in `/usr/share/common-licenses/` |
| `_path_to_result` | `dict` | Global | Fast path→scan_result lookup for enrichment |
| `_unicode_pref` | `dict` | Fix mode | Preferred Unicode author name variants |

---

## Adding New Features — Quick Reference

- **New license mapping**: Add to `SPDX_TO_DEP5` dict (~line 445)
- **New non-free license**: Add to `_NONFREE_RAW` set (~line 2310)
- **New metadata enrichment**: Add a loop after the SVG/KDE/GNOME blocks (~line 940)
- **New review test**: Add after Test 19 in the review block (~line 3150); update verdict logic
- **New check section**: Add after Section 12 in the check block (~line 3510); update summary
- **New interactive fix**: Add as Fix 9 before the write-result block (~line 4576)
- **New compatibility rule**: Add to `check_license_compatibility()` (~line 1211)
- **New false-positive category**: Add to `classify_fp()` (~line 2212) and `FP_LABELS` (~line 3186)
