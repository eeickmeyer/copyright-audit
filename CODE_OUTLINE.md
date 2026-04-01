# Code Outline

`copyright-audit` is a single-file hybrid Bash + Python script (7 512 lines).
The Bash wrapper handles argument parsing, scanner invocation, and environment
setup; the embedded Python (via heredoc) does all analysis, reporting, and
interactive fixing.

---

## Bash Wrapper (lines 1–361)

| Lines | Section | Purpose |
|-------|---------|---------|
| 1–50 | Header / help text | GPL-3 license header, usage documentation |
| 52–95 | Argument parsing | `while` loop over `$@`; sets `MODE`, `EXCLUDE_PATTERNS`, `OUTPUT`, `EXPORT`, `VERBOSE`, `FIX_MODE`, `YES_MODE`, `NO_FETCH`, `JOBS`, `SRCDIR`, `CACHE_DIR` |
| 97–109 | Source-dir resolution | Resolves `SRCDIR` to absolute path; validates `debian/copyright` exists (check/review modes) |
| 111–128 | Scanner detection | Prefers `scancode` → `licensecheck`; requires `python3` |
| 130–156 | Pre-DEP-5 detection | Detects non-machine-readable copyright files; offers to regenerate |
| 158–191 | Temp dir / cache-dir & exclusions | When `--cache-dir` is set, reuses that directory as `_WORKDIR` (skips cleanup on exit); otherwise creates a temp dir. Builds default exclude list (VCS, build artifacts, copyright file itself and all `copyright.*` variants) |
| 193–316 | Run scanner | Invokes scancode (JSON output) or licensecheck (deb-machine text); for each scanner and cross-validation tool, checks `CACHE_DIR` for pre-existing results and skips re-scanning when found; optionally runs cross-validation scans (secondary scanner with `--progress`): licensecheck when scancode is primary, decopy when licensecheck is primary |
| 222–245 | Decopy-accelerated generation | If `generate` mode and `decopy` is installed, runs `decopy --progress .` to seed the initial copyright file (progress bar visible on stderr), then switches to `check` + `fix` + `yes` mode so the full hardening pipeline runs automatically |
| 321–361 | Pass state to Python | Detects packager identity, exports everything as env vars; launches `python3 -` heredoc |

---

## Embedded Python (lines 362–7 510)

### Initialization & Configuration (lines 362–748)

| Lines | Section | Purpose |
|-------|---------|---------|
| 362–388 | Env-var intake | Reads all exported variables into Python globals (incl. `_decopy_generated` flag and `export_file`) |
| 390–397 | Native-package detection | `_is_native_package()` — reads `debian/source/format` |
| 402–420 | Built-in license texts | `_BUILTIN_LICENSE_TEXTS` dict (e.g. Unsplash license) |
| 422–520 | License text fetcher | `fetch_license_text()`, `_fetch_cc_text()`, `_fetch_spdx_text()`, `_fetch_url()`, `format_license_body()` — downloads from SPDX API / Creative Commons |
| 522–633 | DEP-5 license boilerplate | `_gpl_preamble()`, `_lgpl_preamble()`, etc.; `_PREAMBLE_MAP`; `_wrap_dep5_body()`; `_dep5_common_license_body()` — standard DEP-5 license preamble text with version/or-later placeholders and common-licenses pointers |
| 635–695 | Exclusion & metadata helpers | `is_excluded()`, `is_metadata_file()` — glob-matching utilities; `_METADATA_GLOBS` includes `LICENSES/*` / `licenses/*` for REUSE spec |

### License Normalization (lines 751–915)

| Lines | Section | Purpose |
|-------|---------|---------|
| 751–879 | `SPDX_TO_DEP5` | 130+ entry mapping dict from scanner output to DEP-5 names (includes CC-GPL variants) |
| 881–891 | `to_dep5()` | Normalize any license ID to DEP-5 convention |
| 893–899 | `SOURCE_EXTS` | Set of recognized source-code file extensions |
| 901–915 | `norm_cmp()` | Normalize for comparison only (collapses aliases, strips versions) |

### Scan Result Parsing (lines 917–1036)

| Lines | Section | Purpose |
|-------|---------|----------|
| 917–991 | ScanCode JSON parser | Iterates `files[]`, extracts `license_detections` (with confidence filtering → `low_confidence` list) and `copyrights` |
| 993–1033 | licensecheck parser | Parses `--deb-machine` paragraph output |
| 1036 | Symlink filter | Removes symlink entries from `scan_results` |

### Patch-File False-Positive Filter (lines 1038–1082)

| Lines | Section | Purpose |
|-------|---------|----------|
| 1038–1082 | Patch/diff filter | For `.patch`/`.diff` files with scanner-detected licenses but zero copyrights, checks whether ALL license matches fall on unified-diff context lines (lines starting with `+`, `-`, or space). If so, clears the licenses — these belong to the file being patched, not the patch itself |

### Binary Garbage & Implausible Holder Filter (lines 1084–1226)

| Lines | Section | Purpose |
|-------|---------|----------|
| 1084–1091 | `_PRINTABLE_RANGE` | Printable ASCII range for binary garbage detection |
| 1093–1126 | `_CODE_FRAGMENT_RE` | Regex matching C/C++/Qt code patterns, template variables, format strings, and other non-person text that false-positive as copyright holders |
| 1128–1180 | `_NOT_A_HOLDER_RE` | Regex matching license text fragments, disclaimers, build system boilerplate, and other non-name strings extracted as copyright holders |
| 1182–1223 | `_is_plausible_copyright()` | Rejects copyright strings with < 70% printable ASCII, < 3 printable chars, code fragments (`_CODE_FRAGMENT_RE`), or non-holder text (`_NOT_A_HOLDER_RE`); eliminates binary file artifacts and scanner false positives |
| 1225–1226 | Filter application | Applies `_is_plausible_copyright()` to all `scan_results` entries |

### Progress Bar (line 1231)

| Lines | Function | Purpose |
|-------|----------|----------|
| 1231–1239 | `progress()` | Stderr progress bar for large scans |

### Metadata Enrichment (lines 1241–1608)

Overrides scanner heuristics with authoritative embedded metadata.

| Lines | Section | Purpose |
|-------|---------|----------|
| 1252–1255 | Path-to-result index | `_path_to_result` dict for O(1) enrichment lookups |
| 1257–1322 | KDE `metadata.json` | Extracts `KPlugin.Authors`, detects Unsplash URLs, applies to image files via symlink resolution |
| 1324–1413 | SVG RDF/XML metadata | Parses `<cc:license>` and `<dc:creator>` from SVG `<metadata>` — overrides scancode's CC version guesses |
| 1414–1566 | XMP metadata for raster images | Extracts XMP packets from PNG/JPEG/TIFF/WebP/etc. via byte-string search; parses `dc:creator`, `cc:license`, `dc:rights`, `xmpRights:WebStatement`, `photoshop:Credit`, `xmp:CreateDate` — overrides scanner heuristics |
| 1567–1608 | GNOME background XML | Parses `<wallpaper>` elements in `gnome-background-properties/*.xml`, extracts "by Artist" pattern |

### Directory License Inheritance (lines 1610–1695)

| Lines | Section | Purpose |
|-------|---------|----------|
| 1610–1695 | Inheritance logic | Files with no detected license inherit from directory's dominant license — only when a COPYING/LICENSE file exists nearby; skipped for native packages |

### Existing `debian/copyright` Parsing (lines 1697–1755)

| Lines | Section | Purpose |
|-------|---------|---------|
| 1697–1731 | Stanza parser | Populates `stanzas` (glob→license) and `stanza_copyrights` (glob→holders) |
| 1734–1755 | License block parser | Populates `license_blocks` (name→body text) for standalone License paragraphs |

### Validation Functions (lines 1761–2210)

These are pure functions called by both check and review modes.

| Lines | Function | Purpose |
|-------|----------|---------|
| 1761–1851 | `check_license_completeness()` | `SYSTEM_COMMON_LICENSES` setup (line 1761); tries host `/usr/share/common-licenses/` then `$SNAP/usr/share/common-licenses/` as fallback; verifies each referenced license has a text block; checks CC full-text, FIXME stubs, common-licenses refs |
| 1851–1887 | `check_coverage()` | Finds files uncovered by any stanza; finds stale globs matching no file |
| 1889–1981 | `check_license_compatibility()` | Detects known conflicts: Apache+GPL-2, GPL-2-only+GPL-3-only, CDDL+GPL, EPL+GPL, etc. |
| 1983–2143 | `check_dep5_format()` | Structural DEP-5 validation: Format header, field ordering, tabs, trailing whitespace, blank continuation lines, duplicate globs, catch-all stanza, etc. Returns `(line, severity, message, fix_tag)` tuples |
| 2145–2210 | `fix_dep5_format()` | Auto-applies DEP-5 format fixes (trailing whitespace, tabs, blank continuations, missing newline) |

> **Note on `SYSTEM_COMMON_LICENSES`** (line 1761): populated at import time
> from `/usr/share/common-licenses/` and used by both completeness and fix logic.

### Copyright Comparison Utilities (lines 2211–2640)

Includes corporate-suffix awareness (line 2232, `_CORP_SUFFIXES_RE`) to
avoid splitting names like "Rep Invariant Systems, Inc." on commas.

| Lines | Function | Purpose |
|-------|----------|---------|
| 2211–2228 | `get_declared_license()` / `get_declared_copyrights()` | DEP-5 last-match-wins lookup for a filepath |
| 2237–2275 | Email/Unicode helpers | `_deobfuscate_email()`, `_strip_email()`, `_extract_email()`, `_normalize_unicode()` |
| 2280–2334 | `norm_copyright()` / `_parse_copyright()` | Normalize copyright strings; split into (years, author) |
| 2336–2392 | `_split_multi_authors()` | Splits "A, B and C" into individual authors; handles corporate suffixes (Inc., Ltd., GmbH) |
| 2394–2430 | `_infer_years_from_paths()` | Fallback year detection via `git log` (batched) or file mtime |
| 2434–2600 | `merge_copyrights()` | Core deduplication engine: groups years by normalized author, email-based dedup, compressed-key dedup, fuzzy edit-distance dedup, Unicode preference, year-range collapsing |
| 2601–2640 | Formatting helpers | `format_files_field()`, `_copyright_continuations()`, `format_copyright_field()` |

### Copyright Holder Audit (lines 2656–2747)

| Lines | Function | Purpose |
|-------|----------|---------|
| 2656–2747 | `check_copyright_holders()` | Compares detected vs. declared holders per stanza; skips license text files (LICENSE, COPYING) to avoid false positives; returns missing, extra, and per-file attribution maps |

### Stanza Consolidation (lines 2749–2930)

| Lines | Function | Purpose |
|-------|----------|---------|
| 2749–2796 | `_parse_paragraph_stanzas()` | Re-parses copyright text into structured stanza dicts |
| 2798–2851 | `check_consolidation()` | Groups stanzas by (license, holder-set); identifies merge candidates |
| 2853–2930 | `_simplify_file_list()` | Reduces file lists to dir/* globs; merges sibling globs with common prefixes |

### Superfluous Detection (lines 2932–3012)

| Lines | Function | Purpose |
|-------|----------|--------|
| 2932–3012 | `check_superfluous()` | Identifies superfluous stanzas/patterns: (1) all patterns stale → remove stanza, (2) some patterns stale → remove stale only, (3) stanza redundant with catch-all (bidirectional `licenses_compatible()` + copyright-holder subset check) → remove stanza. Returns list of dicts with `stanza`, `reason`, `stale_patterns`, `kept_patterns`, `remove_entirely` |

### False-Positive Classification & Compatibility (lines 3014–3168)

| Lines | Function | Purpose |
|-------|----------|---------|
| 3014–3029 | `classify_fp()` | Classifies likely false-positive mismatches (autoconf boilerplate, LICENSE text files, build files, metadata) |
| 3031–3115 | `licenses_compatible()` | Full GPL/LGPL/AGPL/GFDL family subsumption, BSD/MIT aliases, LGPL→GPL conversion, MPL-2.0 exception |
| 3117–3140 | `_NONFREE_RAW` / `NONFREE` / `is_nonfree()` | Non-free/non-DFSG license detection (SSPL, BUSL, CC-NC, CC-ND, etc.) |
| 3151–3168 | `_warn_stubs()` | Post-write warning for unresolved FIXME/TODO/PLACEHOLDER tokens |

---

## Mode: generate (lines 3170–3540)

Builds a new `debian/copyright` from scan results. **When `decopy` is
installed**, the Bash wrapper runs `decopy .` first to seed the file (lines
222–245), then switches to check+fix+yes mode — so the generate path below
is the fallback when decopy is absent.

| Lines | Section | Purpose |
|-------|---------|---------|
| 3170–3217 | File grouping | Collects per-file data; counts licenses to pick catch-all; groups by (license, author-set) |
| 3218–3270 | `smart_glob()` | Directory-aware glob generation with sibling merging |
| 3272–3363 | Catch-all + per-author stanzas | Emits `Files: *` then per-author stanzas |
| 3363–3420 | `debian/*` stanza proposal | Interactive prompt for packaging stanza (skipped for native packages) |
| 3422–3487 | License text blocks | Common-licenses references, SPDX/CC fetching, FIXME stubs for unfetched |
| 3491–3540 | Warnings & summary | Non-free detection, loud compatibility banner, file/stanza counts |

---

## Mode: check / review — Setup (lines 3545–3738)

| Lines | Section | Purpose |
|-------|---------|---------|
| 3545–3593 | Load auxiliary results | `_parse_dep5_sanity()` parses DEP-5 output from each available secondary scanner into `all_sanity_results` dict |
| 3595–3645 | `run_sanity_check()` | Cross-validates primary vs. one secondary scanner by license family; both sides DEP-5-normalized via `to_dep5()`; skips project-level metadata files (LICENSE, COPYING, AUTHORS, CONTRIBUTORS); called once per secondary tool, results stored in `all_sanity_discrepancies` |
| 3647–3698 | Two-of-three consensus | When ≥2 secondary scanners ran, gathers all flagged paths, compares license families pairwise across tools; files where ≥2 agree → `sanity_consensus` (INFO); files where all disagree → `sanity_real_disc` (WARN) |
| 3700–3738 | Classification loop | Iterates scan results; populates `real_mismatches`, `fp_mismatches`, `no_license`, `apache_files`, `all_scan_licenses` |

---

## Mode: review (lines 3740–4230)

Structured pass/fail report with 19 tests.

| Test | Lines | What it checks |
|------|-------|----------------|
| 1 | 3751 | DEP-5 format validation |
| 2 | 3769 | Catch-all `Files: *` stanza |
| 3 | 3774 | License mismatches (with inline details: detected vs. declared, affected files) |
| 4 | 3786 | Undeclared licenses |
| 5 | 3803 | License compatibility (loud `!`-banner on failure; BLOCKED verdict) |
| 6 | 3819 | Non-free licenses in source |
| 7 | 3829 | Source files without license headers |
| 8 | 3834 | License text completeness |
| 9 | 3849 | Stanza coverage (uncovered files) |
| 10 | 3865 | Stale stanza globs |
| 10b | 3874 | Superfluous stanzas/patterns (entirely removable + stale-pattern stanzas; VERDICT via `superfluous_ok`) |
| 11 | 3904 | Copyright holder accuracy (undeclared = WARN; declared-not-detected = INFO) |
| 13 | 3933 | Low-confidence detections |
| 14 | 3942 | Stanza consolidation opportunities |
| 15 | 3959 | FIXME entries in copyright file |
| 16 | 3980 | Versionless / invalid license identifiers |
| 17 | 3996 | Broad glob override conflicts |
| 18 | 4026 | Duplicate file declarations |
| 19 | 4047 | Scanner cross-validation (2-of-3 consensus: WARN for all-disagree, INFO for consensus, PASS when all agree) |

Ends with verdict (lines 4080–4100) — four tiers: BLOCKED (license incompatibility), complete, minor issues, needs work. Detailed mismatch appendix and optional `--export` full-detail findings writer follow.

---

## Mode: check — Standard Report (lines 4233–4660)

When entered via the decopy-accelerated generate path, stdout is redirected
to stderr (line 4240) so the check report doesn't pollute the copyright output.

| Section | Lines | Content |
|---------|-------|---------|
| 0 | 4249 | DEP-5 format validation |
| 1 | 4267 | License mismatches — needs review |
| 2 | 4300 | Likely false positives (informational) |
| 3 | 4321 | License text completeness |
| 4 | 4341 | License compatibility + non-free warnings (loud `!`-banner) |
| 5 | 4384 | All licenses found in source |
| 6 | 4395 | Stanza coverage analysis |
| 7 | 4480 | Files with no detected license |
| 8 | 4505 | Copyright holder accuracy |
| 9 | 4535 | Stanza consolidation |
| 10 | 4556 | Decopy findings |
| 11 | 4568 | Scanner cross-validation (all-disagree + 2-of-3 consensus subsections) |
| 12 | 4594 | Low-confidence detections |
| Summary | 4607 | Aggregate counts, result verdict |

---

## Interactive Fix Mode (lines 4664–7510)

Entered via `--fix` flag, post-check prompt, or automatically when the
decopy-accelerated generate path is active.

| Fix | Lines | What it does |
|-----|-------|--------------|
| 0 | 4779 | Apply DEP-5 format fixes (whitespace, tabs, blank continuations) |
| 0b | 4797 | Populate header stubs — infers Upstream-Name from `debian/control` Source field, Upstream-Contact from GitHub API (owner profile), package metadata (`setup.py`/`setup.cfg`/`pyproject.toml`/`package.json`), or `debian/control` Maintainer as last resort; fills Source from Homepage; replaces FIXME values in Source, Upstream-Name, and Upstream-Contact; handles GitHub URLs with fragments and sub-paths |
| 0c | 5045 | Remove FSF boilerplate copyright from GPL-family stanzas |
| 0c3 | 5107 | Remove implausible copyright holders — code fragments, template variables, format strings, and non-person text detected by `_CODE_FRAGMENT_RE` and `_NOT_A_HOLDER_RE` |
| 0c4 | 5155 | Remove packager-as-copyright from upstream stanzas — detects when the Debian packager appears as a copyright holder in non-`debian/*` stanzas and removes them |
| 0c5 | 5217 | Trim catch-all Copyright to AUTHORS entries — for `Files: *` stanzas, reads the project's AUTHORS/CONTRIBUTORS file and filters holders to only those who appear as project-level authors |
| 0c2 | 5334 | Add missing Copyright to Files stanzas — infers from scanner data; for `Files: *`, queries GitHub API (repo owner + creation year) or package metadata before packager fallback |
| 0d | 5460 | Remove license text file paths (`LICENSES/*`) from per-file stanzas |
| 1 | 5511 | Add new `Files:` stanzas for mismatched files (per-author grouping) |
| 1c | 5650 | Correct wrong license in existing stanzas — when cross-validation (2+ scanners agree) confirms the primary scanner's detection differs from the declared license, offers to update the stanza in-place |
| 1b | 5773 | Resolve `Unknown` license stanzas — covered by `Files: *` or needs scanner data |
| 2 | 5893 | Remove superfluous files/patterns/stanzas — removes entire stanzas (all-stale or catch-all-redundant), strips stale patterns from partial stanzas, cleans up orphaned standalone `License:` blocks |
| 2b | 6018 | Drop zero-evidence files from specific stanzas — files with no scanner-detected license or copyright have no evidence to support a specific stanza; removes them (or removes entire stanza if all files are zero-evidence) |
| 3 | 6087 | Add missing standalone `License:` text blocks (full DEP-5 boilerplate via `_dep5_common_license_body()` or SPDX fetch) |
| 3b | 6160 | Fix empty/stub standalone license blocks (same boilerplate generation); validates common-licenses references exist before skipping — bogus refs (e.g. CC-BY-SA-3.0) trigger replacement |
| 4 | 6239 | Update copyright holders — adds missing holders; proposes new stanzas instead of polluting `Files: *` |
| 5 | 6538 | Propose `debian/*` packaging stanza, add packager to existing one, or update packager year |
| 6 | 6709 | Consolidate stanzas sharing same license + authors |
| 6b | 6806 | Collapse explicit file lists into dir/* globs — for stanzas with long explicit file lists, detects when all files in a directory are listed and replaces them with `dir/*` globs; includes subdir safety check to avoid over-broad patterns |
| 7 | 6960 | Normalize copyright lines (year ordering, email deobfuscation, brackets) |
| 7b | 7020 | Normalize license names (e.g. `gpl-2+` → `GPL-2+`) |
| 7c | 7049 | Strip stale "No explicit license found" comments from stanzas |
| 7d | 7087 | Remove orphaned standalone License blocks (no longer referenced by any Files stanza) |
| 8 | 7123 | Replace inline license text with `/usr/share/common-licenses/` references (uses `_dep5_common_license_body()`) |
| 0c2-final | 7200 | Late-stage FIXME resolution — 4 strategies: (1) scanner data fnmatch, (2) file header reading for SPDX-License-Identifier, (3) directory COPYRIGHT/AUTHORS files, (4) XML metadata + path-based heuristics. Runs after all other fixes to catch FIXME stanzas created by earlier steps |
| — | ~7442 | Write result: backup `.bak` (skipped in generate pipeline via `_decopy_generated`), write changes, warn about remaining FIXME stubs |

After fix mode, if the decopy-accelerated generate path is active (lines
7504–7510), stdout is restored and the hardened file is emitted to stdout
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
| `SPDX_TO_DEP5` | `dict` | Const | 130+ scanner-output → DEP-5 name mappings (includes CC-GPL variants) |
| `_NONFREE_RAW` | `set` | Const | Non-free/non-DFSG license identifiers |
| `SOURCE_EXTS` | `set` | Const | Recognized source file extensions |
| `_CODE_FRAGMENT_RE` | `re.Pattern` | Const | Regex matching code fragments, template variables, and non-person text |
| `_NOT_A_HOLDER_RE` | `re.Pattern` | Const | Regex matching license text fragments, disclaimers, and build system boilerplate |
| `_PATCH_EXTS` | `set` | Const | File extensions for patch/diff files (`.patch`, `.diff`) |
| `all_sanity_results` | `dict` | Global | `{tool_name: {path: set(licenses)}}` secondary scanner results |
| `all_sanity_discrepancies` | `dict` | Global | `{tool_name: [(path, primary_lics, secondary_lics)]}` pairwise disagreements |
| `sanity_consensus` | `list[tuple]` | Global | `(path, {tool: lics}, consensus_lic)` — files where ≥2 of 3 scanners agree |
| `sanity_real_disc` | `list[tuple]` | Global | `(path, {tool: lics})` — files where all scanners disagree |
| `SYSTEM_COMMON_LICENSES` | `set` | Global | Licenses in `/usr/share/common-licenses/` (host or `$SNAP` fallback) |
| `_path_to_result` | `dict` | Global | Fast path→scan_result lookup for enrichment |
| `_unicode_pref` | `dict` | Fix mode | Preferred Unicode author name variants |

---

## Adding New Features — Quick Reference

- **New license mapping**: Add to `SPDX_TO_DEP5` dict (~line 751)
- **New non-free license**: Add to `_NONFREE_RAW` set (~line 3117)
- **New metadata enrichment**: Add a loop after the SVG/KDE/GNOME blocks (~line 1608)
- **New review test**: Add after Test 19 in the review block (~line 4070); update verdict logic
- **New check section**: Add after Section 12 in the check block (~line 4600); update summary
- **New interactive fix**: Add as Fix 9 before the write-result block (~line 7120)
- **New false-positive filter**: Add to `_CODE_FRAGMENT_RE` (~line 1093) or `_NOT_A_HOLDER_RE` (~line 1128)
- **New implausible holder pattern**: Add to `_NOT_A_HOLDER_RE` (~line 1128) or `_is_plausible_copyright()` (~line 1182)
- **New compatibility rule**: Add to `check_license_compatibility()` (~line 1889)
- **New false-positive category**: Add to `classify_fp()` (~line 3014) and `FP_LABELS` (~line 4284)
- **New license preamble**: Add to the preamble functions (~line 522) and `_PREAMBLE_MAP` (~line 623)
