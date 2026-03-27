# Code Outline

`copyright-audit` is a single-file hybrid Bash + Python script (5 720 lines).
The Bash wrapper handles argument parsing, scanner invocation, and environment
setup; the embedded Python (via heredoc) does all analysis, reporting, and
interactive fixing.

---

## Bash Wrapper (lines 1–268)

| Lines | Section | Purpose |
|-------|---------|---------|
| 1–50 | Header / help text | GPL-3 license header, usage documentation |
| 52–95 | Argument parsing | `while` loop over `$@`; sets `MODE`, `EXCLUDE_PATTERNS`, `OUTPUT`, `EXPORT`, `VERBOSE`, `FIX_MODE`, `YES_MODE`, `NO_FETCH`, `JOBS`, `SRCDIR` |
| 97–109 | Source-dir resolution | Resolves `SRCDIR` to absolute path; validates `debian/copyright` exists (check/review modes) |
| 111–128 | Scanner detection | Prefers `scancode` → `licensecheck`; requires `python3` |
| 130–156 | Temp dir & exclusions | Creates `$_WORKDIR`; builds default exclude list (VCS, build artifacts, copyright file itself) |
| 158–213 | Run scanner | Invokes scancode (JSON output) or licensecheck (deb-machine text); optionally runs cross-validation scans (secondary scanner with `--progress`): licensecheck when scancode is primary, decopy when licensecheck is primary |
| 215–237 | Decopy-accelerated generation | If `generate` mode and `decopy` is installed, runs `decopy --progress .` to seed the initial copyright file (progress bar visible on stderr), then switches to `check` + `fix` + `yes` mode so the full hardening pipeline runs automatically |
| 239–268 | Pass state to Python | Detects packager identity, exports everything as env vars; launches `python3 -` heredoc |

---

## Embedded Python (lines 269–4 623)

### Initialization & Configuration (lines 269–468)

| Lines | Section | Purpose |
|-------|---------|---------|
| 269–290 | Env-var intake | Reads all exported variables into Python globals (incl. `_decopy_generated` flag and `export_file`) |
| 295–306 | Native-package detection | `_is_native_package()` — reads `debian/source/format` |
| 307–325 | Built-in license texts | `_BUILTIN_LICENSE_TEXTS` dict (e.g. Unsplash license) |
| 327–428 | License text fetcher | `fetch_license_text()`, `_fetch_cc_text()`, `_fetch_spdx_text()`, `_fetch_url()`, `format_license_body()` — downloads from SPDX API / Creative Commons |
| 430–468 | Exclusion & metadata helpers | `is_excluded()`, `is_metadata_file()` — glob-matching utilities; `_METADATA_GLOBS` includes `LICENSES/*` / `licenses/*` for REUSE spec |

### DEP-5 License Boilerplate (lines 449–627)

| Lines | Section | Purpose |
|-------|---------|----------|
| 449–550 | Preamble functions | `_gpl_preamble()`, `_lgpl_preamble()`, `_agpl_preamble()`, `_gfdl_preamble()`, `_apache_preamble()`, `_mpl_preamble()`, `_artistic_preamble()`, `_bsd_preamble()`, `_cc0_preamble()` — standard DEP-5 license preamble text with version/or-later placeholders |
| 551–562 | `_PREAMBLE_MAP` | Maps license-name prefix to preamble function |
| 563–576 | `_wrap_dep5_body()` | Re-wraps DEP-5 body lines exceeding 79 columns at word boundaries |
| 577–627 | `_dep5_common_license_body()` | Builds full DEP-5 license body (preamble + common-licenses pointer) for any license in `/usr/share/common-licenses/` |

### License Normalization (lines 674–822)

| Lines | Section | Purpose |
|-------|---------|---------|
| 674–787 | `SPDX_TO_DEP5` | 130+ entry mapping dict from scanner output to DEP-5 names |
| 788–798 | `to_dep5()` | Normalize any license ID to DEP-5 convention |
| 800–807 | `SOURCE_EXTS` | Set of recognized source-code file extensions |
| 808–822 | `norm_cmp()` | Normalize for comparison only (collapses aliases, strips versions) |

### Scan Result Parsing (lines 824–950)

| Lines | Section | Purpose |
|-------|---------|----------|
| 824–893 | ScanCode JSON parser | Iterates `files[]`, extracts `license_detections` (with confidence filtering → `low_confidence` list) and `copyrights` |
| 895–938 | licensecheck parser | Parses `--deb-machine` paragraph output |
| 940–950 | `progress()` | Stderr progress bar for large scans |

### Binary Garbage Filter (line 952)

| Lines | Function | Purpose |
|-------|----------|----------|
| 952–968 | `_is_plausible_copyright()` | Rejects copyright strings with < 70% printable ASCII or < 3 printable chars, eliminating binary file artifacts |

### Metadata Enrichment (lines 758–1130)

Overrides scanner heuristics with authoritative embedded metadata.

| Lines | Section | Purpose |
|-------|---------|----------|
| 763–766 | Path-to-result index | `_path_to_result` dict for O(1) enrichment lookups |
| 769–834 | KDE `metadata.json` | Extracts `KPlugin.Authors`, detects Unsplash URLs, applies to image files via symlink resolution |
| 836–942 | SVG RDF/XML metadata | Parses `<cc:license>` and `<dc:creator>` from SVG `<metadata>` — overrides scancode's CC version guesses |
| 944–1095 | XMP metadata for raster images | Extracts XMP packets from PNG/JPEG/TIFF/WebP/etc. via byte-string search; parses `dc:creator`, `cc:license`, `dc:rights`, `xmpRights:WebStatement`, `photoshop:Credit`, `xmp:CreateDate` — overrides scanner heuristics |
| 1097–1130 | GNOME background XML | Parses `<wallpaper>` elements in `gnome-background-properties/*.xml`, extracts "by Artist" pattern |

### Directory License Inheritance (lines 1140–1220)

| Lines | Section | Purpose |
|-------|---------|----------|
| 1140–1220 | Inheritance logic | Files with no detected license inherit from directory's dominant license — only when a COPYING/LICENSE file exists nearby; skipped for native packages |

### Existing `debian/copyright` Parsing (lines 1052–1118)

| Lines | Section | Purpose |
|-------|---------|---------|
| 1054–1088 | Stanza parser | Populates `stanzas` (glob→license) and `stanza_copyrights` (glob→holders) |
| 1089–1118 | License block parser | Populates `license_blocks` (name→body text) for standalone License paragraphs |

### Validation Functions (lines 1114–1555)

These are pure functions called by both check and review modes.

| Lines | Function | Purpose |
|-------|----------|---------|
| 1114–1196 | `check_license_completeness()` | `SYSTEM_COMMON_LICENSES` setup (line 1122); tries host `/usr/share/common-licenses/` then `$SNAP/usr/share/common-licenses/` as fallback; verifies each referenced license has a text block; checks CC full-text, FIXME stubs, common-licenses refs |
| 1198–1234 | `check_coverage()` | Finds files uncovered by any stanza; finds stale globs matching no file |
| 1236–1328 | `check_license_compatibility()` | Detects known conflicts: Apache+GPL-2, GPL-2-only+GPL-3-only, CDDL+GPL, EPL+GPL, etc. |
| 1330–1490 | `check_dep5_format()` | Structural DEP-5 validation: Format header, field ordering, tabs, trailing whitespace, blank continuation lines, duplicate globs, catch-all stanza, etc. Returns `(line, severity, message, fix_tag)` tuples |
| 1492–1555 | `fix_dep5_format()` | Auto-applies DEP-5 format fixes (trailing whitespace, tabs, blank continuations, missing newline) |

> **Note on `SYSTEM_COMMON_LICENSES`** (line 1114): populated at import time
> from `/usr/share/common-licenses/` and used by both completeness and fix logic.

### Copyright Comparison Utilities (lines 1557–1977)

Includes corporate-suffix awareness (line 1576, `_CORP_SUFFIXES_RE`) to
avoid splitting names like "Rep Invariant Systems, Inc." on commas.

| Lines | Function | Purpose |
|-------|----------|---------|
| 1557–1575 | `get_declared_license()` / `get_declared_copyrights()` | DEP-5 last-match-wins lookup for a filepath |
| 1583–1617 | Email/Unicode helpers | `_deobfuscate_email()`, `_strip_email()`, `_extract_email()` |
| 1619–1661 | `norm_copyright()` / `_parse_copyright()` | Normalize copyright strings; split into (years, author) |
| 1663–1718 | `_split_multi_authors()` | Splits "A, B and C" into individual authors; handles corporate suffixes (Inc., Ltd., GmbH) |
| 1721–1758 | `_infer_years_from_paths()` | Fallback year detection via `git log` (batched) or file mtime |
| 1761–1922 | `merge_copyrights()` | Core deduplication engine: groups years by normalized author, email-based dedup, compressed-key dedup, fuzzy edit-distance dedup, Unicode preference, year-range collapsing |
| 1924–1977 | Formatting helpers | `format_files_field()`, `_copyright_continuations()`, `format_copyright_field()` |

### Copyright Holder Audit (lines 1979–2050)

| Lines | Function | Purpose |
|-------|----------|---------|
| 1979–2050 | `check_copyright_holders()` | Compares detected vs. declared holders per stanza; skips license text files (LICENSE, COPYING) to avoid false positives; returns missing, extra, and per-file attribution maps |

### Stanza Consolidation (lines 2052–2232)

| Lines | Function | Purpose |
|-------|----------|---------|
| 2055–2102 | `_parse_paragraph_stanzas()` | Re-parses copyright text into structured stanza dicts |
| 2104–2156 | `check_consolidation()` | Groups stanzas by (license, holder-set); identifies merge candidates |
| 2159–2232 | `_simplify_file_list()` | Reduces file lists to dir/* globs; merges sibling globs with common prefixes |

### Superfluous Detection (lines 2645–2722)

| Lines | Function | Purpose |
|-------|----------|--------|
| 2645–2722 | `check_superfluous()` | Identifies superfluous stanzas/patterns: (1) all patterns stale → remove stanza, (2) some patterns stale → remove stale only, (3) stanza redundant with catch-all (bidirectional `licenses_compatible()` + copyright-holder subset check) → remove stanza. Returns list of dicts with `stanza`, `reason`, `stale_patterns`, `kept_patterns`, `remove_entirely` |

### False-Positive Classification & Compatibility (lines 2234–2387)

| Lines | Function | Purpose |
|-------|----------|---------|
| 2237–2252 | `classify_fp()` | Classifies likely false-positive mismatches (autoconf boilerplate, LICENSE text files, build files, metadata) |
| 2254–2353 | `licenses_compatible()` | Full GPL/LGPL/AGPL/GFDL family subsumption, BSD/MIT aliases, LGPL→GPL conversion, MPL-2.0 exception |
| 2340–2369 | `_NONFREE_RAW` / `NONFREE` / `is_nonfree()` | Non-free/non-DFSG license detection (SSPL, BUSL, CC-NC, CC-ND, etc.) |
| 2374–2387 | `_warn_stubs()` | Post-write warning for unresolved FIXME/TODO/PLACEHOLDER tokens |

---

## Mode: generate (lines 2393–2740)

Builds a new `debian/copyright` from scan results. **When `decopy` is
installed**, the Bash wrapper runs `decopy .` first to seed the file (lines
215–237), then switches to check+fix+yes mode — so the generate path below
is the fallback when decopy is absent.

| Lines | Section | Purpose |
|-------|---------|---------|
| 2393–2455 | File grouping | Collects per-file data; counts licenses to pick catch-all; groups by (license, author-set) |
| 2458–2510 | `smart_glob()` | Directory-aware glob generation with sibling merging |
| 2512–2563 | Catch-all + per-author stanzas | Emits `Files: *` then per-author stanzas |
| 2565–2638 | `debian/*` stanza proposal | Interactive prompt for packaging stanza (skipped for native packages) |
| 2641–2704 | License text blocks | Common-licenses references, SPDX/CC fetching, FIXME stubs for unfetched |
| 2707–2740 | Warnings & summary | Non-free detection, loud compatibility banner, file/stanza counts |

---

## Mode: check / review — Setup (lines 2942–3100)

| Lines | Section | Purpose |
|-------|---------|---------|
| 2942–2992 | Load auxiliary results | `_parse_dep5_sanity()` parses DEP-5 output from each available secondary scanner into `all_sanity_results` dict |
| 2994–3041 | `run_sanity_check()` | Cross-validates primary vs. one secondary scanner by license family; both sides DEP-5-normalized via `to_dep5()`; skips project-level metadata files (LICENSE, COPYING, AUTHORS, CONTRIBUTORS); called once per secondary tool, results stored in `all_sanity_discrepancies` |
| 3046–3096 | Two-of-three consensus | When ≥2 secondary scanners ran, gathers all flagged paths, compares license families pairwise across tools; files where ≥2 agree → `sanity_consensus` (INFO); files where all disagree → `sanity_real_disc` (WARN) |
| 3097–3100 | Classification loop | Iterates scan results; populates `real_mismatches`, `fp_mismatches`, `no_license`, `apache_files`, `all_scan_licenses` |

---

## Mode: review (lines 3133–3583)

Structured pass/fail report with 19 tests.

| Test | Lines | What it checks |
|------|-------|----------------|
| 1 | 3375 | DEP-5 format validation |
| 2 | 3393 | Catch-all `Files: *` stanza |
| 3 | 3398 | License mismatches (with inline details: detected vs. declared, affected files) |
| 4 | 3410 | Undeclared licenses |
| 5 | 3427 | License compatibility (loud `!`-banner on failure; BLOCKED verdict) |
| 6 | 3443 | Non-free licenses in source |
| 7 | 3453 | Source files without license headers |
| 8 | 3458 | License text completeness |
| 9 | 3473 | Stanza coverage (uncovered files) |
| 10 | 3489 | Stale stanza globs |
| 10b | 3581 | Superfluous stanzas/patterns (entirely removable + stale-pattern stanzas; VERDICT via `superfluous_ok`) |
| 11 | 3503 | Copyright holder accuracy (undeclared = WARN; declared-not-detected = INFO) |
| 12 | 3530 | Decopy findings |
| 13 | 3532 | Low-confidence detections |
| 14 | 3541 | Stanza consolidation opportunities |
| 15 | 3558 | FIXME entries in copyright file |
| 16 | 3579 | Versionless / invalid license identifiers |
| 17 | 3595 | Broad glob override conflicts |
| 18 | 3625 | Duplicate file declarations |
| 19 | 3646 | Scanner cross-validation (2-of-3 consensus: WARN for all-disagree, INFO for consensus, PASS when all agree) |

Ends with verdict (lines 3680–3700) — four tiers: BLOCKED (license incompatibility), complete, minor issues, needs work. Detailed mismatch appendix and optional `--export` full-detail findings writer follow.

---

## Mode: check — Standard Report (lines 3584–3981)

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
| 11 | 3888 | Scanner cross-validation (all-disagree + 2-of-3 consensus subsections) |
| 12 | 3506 | Low-confidence detections |
| Summary | 3518 | Aggregate counts, result verdict |

---

## Interactive Fix Mode (lines 3982–5035)

Entered via `--fix` flag, post-check prompt, or automatically when the
decopy-accelerated generate path is active.

| Fix | Lines | What it does |
|-----|-------|--------------|
| 0 | 4343 | Apply DEP-5 format fixes (whitespace, tabs, blank continuations) |
| 0b | 4361 | Populate header stubs (Upstream-Name, Source, Upstream-Contact from `debian/control`) |
| 0c | 4435 | Remove FSF boilerplate copyright from GPL-family stanzas |
| 0d | 4497 | Remove license text file paths (`LICENSES/*`) from per-file stanzas |
| 1 | 4548 | Add new `Files:` stanzas for mismatched files (per-author grouping) |
| 1b | 4687 | Resolve `Unknown` license stanzas — covered by `Files: *` or needs scanner data |
| 2 | 4948 | Remove superfluous files/patterns/stanzas — removes entire stanzas (all-stale or catch-all-redundant), strips stale patterns from partial stanzas, cleans up orphaned standalone `License:` blocks |
| 3 | 4841 | Add missing standalone `License:` text blocks (full DEP-5 boilerplate via `_dep5_common_license_body()` or SPDX fetch) |
| 3b | 4911 | Fix empty/stub standalone license blocks (same boilerplate generation) |
| 4 | 4976 | Update copyright holders — adds missing holders; proposes new stanzas instead of polluting `Files: *` |
| 5 | 5272 | Propose `debian/*` packaging stanza, add packager to existing one, or update packager year |
| 6 | 5443 | Consolidate stanzas sharing same license + authors |
| 7 | 5540 | Normalize copyright lines (year ordering, email deobfuscation, brackets) |
| 8 | 5600 | Replace inline license text with `/usr/share/common-licenses/` references (uses `_dep5_common_license_body()`) |
| — | 5680 | Write result: backup `.bak` (skipped in generate pipeline via `_decopy_generated`), write changes, warn about remaining FIXME stubs |

After fix mode, if the decopy-accelerated generate path is active (lines
4609–4620), stdout is restored and the hardened file is emitted to stdout
(or confirmed at the `-o` path).

---

## Snap Packaging (`snap/snapcraft.yaml`)

The project includes a snap package definition for distribution via the
Snap Store. Key design decisions:

| Aspect | Detail |
|--------|--------|
| Base | `core24` |
| Confinement | `strict` — accesses home, removable-media, and network via plugs |
| Common licenses | `base-files` in a dedicated part, filtered to `usr/share/common-licenses/` only, so `SYSTEM_COMMON_LICENSES` resolves from `$SNAP` |
| Scanner | `scancode-toolkit` installed in a self-contained venv at `$SNAP/scancode/` |
| Serial pool patch | `scancode/pool.py` is replaced at build time with a serial executor to avoid `multiprocessing.Pool` semaphore blocks under strict confinement |
| Runtime deps | `python3`, `git`, `sed`, `coreutils`, `licensecheck`, `decopy`, `libgomp1` |
| Lint ignores | `ctypes`-loaded `.so` files from `extractcode_libarchive`, `typecode_libmagic`, and `libgomp` |
| Environment | `PATH`, `PYTHONPATH`, `PYTHONUNBUFFERED`, `PERL5LIB`, `GIT_EXEC_PATH`, `GIT_TEMPLATE_DIR` all set to resolve in-snap paths |

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
| `all_sanity_results` | `dict` | Global | `{tool_name: {path: set(licenses)}}` secondary scanner results |
| `all_sanity_discrepancies` | `dict` | Global | `{tool_name: [(path, primary_lics, secondary_lics)]}` pairwise disagreements |
| `sanity_consensus` | `list[tuple]` | Global | `(path, {tool: lics}, consensus_lic)` — files where ≥2 of 3 scanners agree |
| `sanity_real_disc` | `list[tuple]` | Global | `(path, {tool: lics})` — files where all scanners disagree |
| `SYSTEM_COMMON_LICENSES` | `set` | Global | Licenses in `/usr/share/common-licenses/` (host or `$SNAP` fallback) |
| `_path_to_result` | `dict` | Global | Fast path→scan_result lookup for enrichment |
| `_unicode_pref` | `dict` | Fix mode | Preferred Unicode author name variants |

---

## Adding New Features — Quick Reference

- **New license mapping**: Add to `SPDX_TO_DEP5` dict (~line 674)
- **New non-free license**: Add to `_NONFREE_RAW` set (~line 2540)
- **New metadata enrichment**: Add a loop after the SVG/KDE/GNOME blocks (~line 1130)
- **New review test**: Add after Test 19 in the review block (~line 3670); update verdict logic
- **New check section**: Add after Section 12 in the check block (~line 4200); update summary
- **New interactive fix**: Add as Fix 9 before the write-result block (~line 5680)
- **New compatibility rule**: Add to `check_license_compatibility()` (~line 1626)
- **New false-positive category**: Add to `classify_fp()` (~line 2437) and `FP_LABELS` (~line 3880)
- **New license preamble**: Add to the preamble functions (~line 540) and `_PREAMBLE_MAP` (~line 551)
