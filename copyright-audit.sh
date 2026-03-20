#!/bin/bash
# copyright-check.sh — Debian copyright file generator, checker, and reviewer
#
# Uses ScanCode Toolkit (SPDX license database) when available for high-
# accuracy detection, falling back to licensecheck otherwise. Can generate
# a new debian/copyright, check an existing one, or produce a reviewer report.
#
# Usage:
#   copyright-check.sh [mode] [options] [source-dir]
#
# Modes:
#   check      Validate existing debian/copyright (default)
#   generate   Scan source tree and produce a new debian/copyright on stdout
#   review     Reviewer mode: structured pass/fail report for archive review
#
# Options:
#   -e, --exclude PATTERN   Glob pattern to exclude from scan (repeatable)
#   -o, --output FILE       Write generated copyright to FILE (generate mode)
#   -f, --fix               Interactively fix issues found (check mode only)
#   --yes                   Auto-accept all fixes (use with --fix, no prompts)
#   -v, --verbose           Show all mismatches including likely false positives
#   -j, --jobs N            Parallel scancode workers (default: nproc)
#   -h, --help              Show this help
#
# Scanner preference (automatic):
#   1. scancode  — SPDX database, highest accuracy (pip install scancode-toolkit)
#   2. licensecheck + decopy — Debian-native tools (apt install licensecheck
#      python3-decopy)
#
# If source-dir is omitted, the current directory is used.
# Requires: python3
# At least one of: scancode-toolkit (pip), licensecheck (apt)

set -euo pipefail

MODE="check"
EXCLUDE_PATTERNS=()
OUTPUT=""
VERBOSE=false
FIX_MODE=false
YES_MODE=false
JOBS=""
SRCDIR=""

show_help() {
    sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        check|generate|review)
            MODE="$1"; shift ;;
        -e|--exclude)
            EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
        -o|--output)
            OUTPUT="$2"; shift 2 ;;
        -f|--fix)
            FIX_MODE=true; shift ;;
        --yes)
            YES_MODE=true; shift ;;
        -v|--verbose)
            VERBOSE=true; shift ;;
        -j|--jobs)
            JOBS="$2"; shift 2 ;;
        -h|--help)
            show_help ;;
        -*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            SRCDIR="$1"; shift ;;
    esac
done

SRCDIR="${SRCDIR:-.}"
SRCDIR="$(cd "$SRCDIR" && pwd)"

if [[ "$MODE" != "generate" ]]; then
    COPYRIGHT_FILE="$SRCDIR/debian/copyright"
    if [[ ! -f "$COPYRIGHT_FILE" ]]; then
        echo "Error: $COPYRIGHT_FILE not found." >&2
        echo "  Use 'generate' mode to create one, or run from a debian source tree." >&2
        exit 1
    fi
else
    COPYRIGHT_FILE=""
fi

# ── Detect available scanner ──────────────────────────────────────────
SCANNER=""
if command -v scancode >/dev/null 2>&1; then
    SCANNER="scancode"
elif command -v licensecheck >/dev/null 2>&1; then
    SCANNER="licensecheck"
else
    echo "Error: No license scanner found." >&2
    echo "  Install one of:" >&2
    echo "    pip install scancode-toolkit   (recommended, uses SPDX database)" >&2
    echo "    sudo apt install licensecheck  (basic, Debian-native)" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required." >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Debian Copyright Tool ===" >&2
echo "Mode:    $MODE" >&2
echo "Source:  $SRCDIR" >&2
echo "Scanner: $SCANNER" >&2
[[ -n "$COPYRIGHT_FILE" ]] && echo "Copyright: $COPYRIGHT_FILE" >&2
if [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]]; then
    echo "Excluding: ${EXCLUDE_PATTERNS[*]}" >&2
fi
echo "" >&2

# ── Run scanner ───────────────────────────────────────────────────────
cd "$SRCDIR"

if [[ "$SCANNER" == "scancode" ]]; then
    echo "Running ScanCode (SPDX database)... this may take several minutes." >&2
    SC_ARGS=(--license --copyright --json "$TMPDIR/scancode.json" --quiet)
    if [[ -n "$JOBS" ]]; then
        SC_ARGS+=(-n "$JOBS")
    fi
    scancode "${SC_ARGS[@]}" . 2>/dev/null
    SCAN_FILE="$TMPDIR/scancode.json"
else
    echo "Running licensecheck..." >&2
    licensecheck -r --deb-machine . 2>/dev/null \
        | sed 's/[\x00-\x08\x0e-\x1f]//g' \
        > "$TMPDIR/licensecheck.txt"
    SCAN_FILE="$TMPDIR/licensecheck.txt"

    # Also run decopy if available and in check/review mode
    if [[ "$MODE" != "generate" ]] && command -v decopy >/dev/null 2>&1; then
        echo "Running decopy..." >&2
        decopy --mode full --copyright-file "$COPYRIGHT_FILE" --quiet . \
            > "$TMPDIR/decopy.txt" 2>&1 || true
    fi
fi

echo "Analyzing..." >&2
echo "" >&2

# ── Pass state to Python ─────────────────────────────────────────────
EXCLUDE_STR="$(printf '%s\n' "${EXCLUDE_PATTERNS[@]+"${EXCLUDE_PATTERNS[@]}"}")"
export EXCLUDE_STR VERBOSE FIX_MODE YES_MODE SCANNER MODE COPYRIGHT_FILE OUTPUT

python3 - "$SCAN_FILE" << 'PYEOF'
import json, os, re, sys, fnmatch, textwrap
from collections import defaultdict, OrderedDict
from pathlib import Path

scan_file = sys.argv[1]
scanner = os.environ.get("SCANNER", "licensecheck")
mode = os.environ.get("MODE", "check")
copyright_file = os.environ.get("COPYRIGHT_FILE", "")
output_file = os.environ.get("OUTPUT", "")
verbose = os.environ.get("VERBOSE", "false") == "true"
fix_mode = os.environ.get("FIX_MODE", "false") == "true"
yes_mode = os.environ.get("YES_MODE", "false") == "true"

exclude_raw = os.environ.get("EXCLUDE_STR", "").strip()
excludes = [p for p in exclude_raw.split("\n") if p]

def is_excluded(filepath):
    fp = filepath.lstrip("./")
    return any(fnmatch.fnmatch(fp, pat) for pat in excludes)

# ══════════════════════════════════════════════════════════════════════
# SPDX license ID normalization (maps scanner output -> DEP-5 names)
# ══════════════════════════════════════════════════════════════════════
SPDX_TO_DEP5 = {
    "mit": "Expat", "expat": "Expat", "x11": "Expat",
    "mit~old": "Expat", "mit-cmu": "Expat",
    "bsd-3-clause": "BSD-3-Clause", "bsd-3-clause-no-nuclear-license": "BSD-3-Clause",
    "bsd-2-clause": "BSD-2-Clause", "bsd-2-clause-views": "BSD-2-Clause",
    "bsd-2-clause-freebsd": "BSD-2-Clause",
    "apache-2.0": "Apache-2.0",
    "gpl-2.0-only": "GPL-2", "gpl-2.0-or-later": "GPL-2+",
    "gpl-2": "GPL-2", "gpl-2+": "GPL-2+",
    "gpl-3.0-only": "GPL-3", "gpl-3.0-or-later": "GPL-3+",
    "lgpl-2.1-only": "LGPL-2.1", "lgpl-2.1-or-later": "LGPL-2.1+",
    "lgpl-2.1": "LGPL-2.1", "lgpl-2.1+": "LGPL-2.1+",
    "mpl-2.0": "MPL-2.0",
    "isc": "ISC",
    "cc-by-sa-4.0": "CC-BY-SA-4.0", "cc-by-sa-3.0": "CC-BY-SA-3.0",
    "zlib": "Zlib",
    "ofl-1.1": "OFL-1.1",
    "sgi-b-2.0": "SGI-B-2.0",
    "hpnd-sell-variant": "HPND-sell-variant",
    "bsl-1.0": "BSL-1.0",
    "unlicense": "Unlicense",
    "public-domain": "public-domain",
    "fsfap": "FSFAP",
}

def to_dep5(raw):
    """Normalize a license identifier to DEP-5 convention."""
    s = raw.lower().strip().rstrip("+")
    plus = raw.strip().endswith("+") or "-or-later" in raw.lower()
    base = SPDX_TO_DEP5.get(s, None)
    if base is None:
        base = SPDX_TO_DEP5.get(s + "+" if plus else s, raw.strip())
    if plus and not base.endswith("+"):
        base += "+"
    return base

def norm_cmp(lic):
    """Normalize for comparison only (lowercase, collapse variants)."""
    s = lic.lower().strip()
    s = re.sub(r'\.0', '', s)
    s = s.replace("-or-later", "+").replace("-only", "")
    ALIASES = {
        "expat": "expat", "mit": "expat", "x11": "expat",
        "mit~old": "expat", "mit-cmu": "expat",
    }
    return ALIASES.get(s, s)

# ══════════════════════════════════════════════════════════════════════
# Parse scan results into unified format
# ══════════════════════════════════════════════════════════════════════
# Result: list of {"path": str, "licenses": [str], "copyrights": [str]}
scan_results = []

if scanner == "scancode":
    with open(scan_file) as f:
        data = json.load(f)
    for entry in data.get("files", []):
        if entry.get("type") != "file":
            continue
        path = "./" + entry["path"].lstrip("./")
        if is_excluded(path):
            continue
        lics = []
        for det in entry.get("license_detections", []):
            spdx = det.get("license_expression_spdx", "") or ""
            if spdx:
                # Split compound expressions
                for part in re.split(r'\s+AND\s+|\s+OR\s+', spdx):
                    part = part.strip("() ")
                    if part:
                        lics.append(part)
            else:
                expr = det.get("license_expression", "") or ""
                for part in re.split(r'\s+AND\s+|\s+OR\s+', expr):
                    part = part.strip("() ")
                    if part:
                        lics.append(part)
        cops = []
        for c in entry.get("copyrights", []):
            val = c.get("copyright", "")
            if val:
                cops.append(val)
        # De-duplicate
        lics = list(dict.fromkeys(lics))
        cops = list(dict.fromkeys(cops))
        scan_results.append({"path": path, "licenses": lics, "copyrights": cops})
else:
    # Parse licensecheck --deb-machine output
    with open(scan_file) as f:
        content = f.read()
    SKIP_LIC = {"UNKNOWN", "FSFAP", "FSFULLR", "FSFUL"}
    for para in content.split("\n\n"):
        para = para.strip()
        if not para.startswith("Files:"):
            continue
        lines = para.split("\n")
        file_lines = []
        lic_line = None
        cop_line = None
        in_files = True
        for line in lines:
            if line.startswith("Files:"):
                rest = line[6:].strip()
                if rest:
                    file_lines.append(rest)
                in_files = True
            elif line.startswith("Copyright:"):
                in_files = False
                cop_line = line[10:].strip()
            elif line.startswith("License:"):
                in_files = False
                lic_line = line[8:].strip()
            elif in_files and line.startswith(" "):
                file_lines.append(line.strip())
        for fp in file_lines:
            if is_excluded(fp):
                continue
            lics = []
            if lic_line and lic_line not in SKIP_LIC:
                # licensecheck uses "and/or" for dual-license
                for part in re.split(r'\s+and/or\s+', lic_line):
                    part = part.strip("() ")
                    # Strip "with ... exception"
                    base = re.split(r'\s+with\s+', part, flags=re.IGNORECASE)[0].strip()
                    if base:
                        lics.append(base)
            cops = [cop_line] if cop_line else []
            scan_results.append({"path": fp, "licenses": lics, "copyrights": cops})

# ══════════════════════════════════════════════════════════════════════
# Parse existing debian/copyright
# ══════════════════════════════════════════════════════════════════════
stanzas = []  # [(glob, license_id)]
if copyright_file and os.path.isfile(copyright_file):
    with open(copyright_file) as f:
        copyright_text = f.read()
    for para in copyright_text.split("\n\n"):
        files = []
        lic = None
        current_field = None  # Track which field continuation lines belong to
        for line in para.split("\n"):
            if line.startswith("Files:"):
                rest = line[6:].strip()
                if rest:
                    files.extend(rest.split())
                current_field = "files"
            elif line.startswith("Copyright:"):
                current_field = "copyright"
            elif line.startswith("License:"):
                lic = line[8:].strip().split()[0] if line[8:].strip() else None
                current_field = "license"
            elif current_field == "files" and line.startswith("       "):
                files.extend(line.strip().split())
        if files and lic:
            for f in files:
                stanzas.append((f, lic))

# Also parse standalone License text blocks
license_blocks = {}  # {license_name: text_body}
if copyright_file and os.path.isfile(copyright_file):
    for para in copyright_text.split("\n\n"):
        lines = para.split("\n")
        if not lines:
            continue
        first = lines[0]
        has_files = any(l.startswith("Files:") for l in lines)
        if first.startswith("License:") and not has_files:
            lic_name = first[8:].strip().split()[0] if first[8:].strip() else None
            if lic_name:
                body_lines = []
                for l in lines[1:]:
                    # DEP-5: continuation lines start with space or " ."
                    if l.startswith(" ") or l == " .":
                        body_lines.append(l[1:] if l.startswith(" ") else "")
                    elif l.strip() == ".":
                        body_lines.append("")
                license_blocks[lic_name] = "\n".join(body_lines)

# ══════════════════════════════════════════════════════════════════════
# License text completeness checking
# ══════════════════════════════════════════════════════════════════════

# Licenses available in /usr/share/common-licenses/ on this system
SYSTEM_COMMON_LICENSES = set()
try:
    for entry in os.listdir("/usr/share/common-licenses"):
        SYSTEM_COMMON_LICENSES.add(entry)
        # Also map short names: GPL-2+ -> GPL-2 exists
except OSError:
    pass

def check_license_completeness():
    """Check each referenced license has a complete text block.

    Returns list of (license_name, severity, message) tuples.
    severity: 'error', 'warning', 'info'
    """
    issues = []
    # Collect all licenses referenced by file stanzas
    referenced = set(lic for _, lic in stanzas)
    if not referenced:
        return issues

    for lic in sorted(referenced):
        slug = lic.rstrip("+")

        # Check if it has a standalone License block
        if lic not in license_blocks:
            issues.append((lic, "error",
                f"No standalone License block found for '{lic}'"))
            continue

        body = license_blocks[lic]
        body_stripped = body.strip()
        body_lines = [l for l in body_stripped.split("\n") if l.strip()]
        text_len = len(body_stripped)

        # Check for FIXME/TODO placeholders
        if re.search(r'FIXME|TODO|PLACEHOLDER', body_stripped, re.IGNORECASE):
            issues.append((lic, "error",
                f"License '{lic}' contains FIXME/TODO placeholder"))
            continue

        # Check if it references /usr/share/common-licenses/
        cl_ref = re.search(r'/usr/share/common-licenses/([\w.+-]+)', body_stripped)
        if cl_ref:
            ref_name = cl_ref.group(1)
            if ref_name not in SYSTEM_COMMON_LICENSES and slug not in SYSTEM_COMMON_LICENSES:
                issues.append((lic, "error",
                    f"License '{lic}' references /usr/share/common-licenses/{ref_name} "
                    f"but that file does not exist on this system"))
            else:
                # Valid common-licenses reference, that's sufficient
                continue

        # ── Creative Commons specific checks ──
        # lintian specifically checks for incomplete CC licenses
        if re.match(r'^CC-BY', lic, re.IGNORECASE):
            # CC licenses are verbose — full text is typically 10KB+
            # A summary/abstract is usually < 2KB
            if text_len < 3000:
                issues.append((lic, "warning",
                    f"License '{lic}' appears to be a summary, not the full legal text "
                    f"({text_len} chars, full text is typically 10000+). "
                    f"lintian will flag this as 'incomplete-creative-commons-license'"))
                continue
            # Check for key full-text markers
            if not re.search(r'Section\s+[1-8]|BY EXERCISING|Creative Commons Corporation',
                             body_stripped):
                issues.append((lic, "warning",
                    f"License '{lic}' may not be the full legal text "
                    f"(missing expected legal code markers)"))
                continue

        # ── General completeness check ──
        # A real license text should have substantial content
        # Most open source licenses are at least 500 chars
        if text_len < 50:
            issues.append((lic, "error",
                f"License '{lic}' text block is nearly empty ({text_len} chars)"))
        elif text_len < 200 and slug not in SYSTEM_COMMON_LICENSES:
            issues.append((lic, "warning",
                f"License '{lic}' text block is very short ({text_len} chars) "
                f"and not in /usr/share/common-licenses/"))

    return issues

def check_coverage():
    """Check stanza coverage vs actual source files.

    Returns:
        uncovered: list of (filepath, detected_licenses) not matched by any stanza
        stale: list of (glob_pattern, license) that match no scanned file
    """
    # All scanned file paths (stripped of ./)
    scanned_paths = set(r["path"].lstrip("./") for r in scan_results)

    # 1) Files not covered by any stanza glob
    uncovered = []
    for r in scan_results:
        fp = r["path"].lstrip("./")
        matched = False
        for glob_pat, _ in stanzas:
            if fnmatch.fnmatch(fp, glob_pat) or glob_pat == "*":
                matched = True
                break
        if not matched:
            lics = [to_dep5(l) for l in r["licenses"]] if r["licenses"] else []
            uncovered.append((fp, lics))

    # 2) Stanza globs that match no scanned file (stale entries)
    stale = []
    seen_globs = set()
    for glob_pat, lic in stanzas:
        if glob_pat == "*":  # catch-all always "matches"
            continue
        if glob_pat in seen_globs:
            continue
        seen_globs.add(glob_pat)
        has_match = any(fnmatch.fnmatch(sp, glob_pat) for sp in scanned_paths)
        if not has_match:
            stale.append((glob_pat, lic))

    return uncovered, stale

def check_dep5_format():
    """Validate DEP-5 structural/format compliance of debian/copyright.

    Returns list of (line_number, severity, message, fix_tag) tuples.
    fix_tag is a string identifying the auto-fix category, or None.
    """
    issues = []
    if not copyright_file or not os.path.isfile(copyright_file):
        return issues

    with open(copyright_file) as f:
        raw = f.read()
    lines = raw.split("\n")

    # ── 1. Header paragraph: must start with Format: ─────────────
    paragraphs = raw.split("\n\n")
    if paragraphs:
        header = paragraphs[0]
        header_lines = header.split("\n")
        if not header_lines or not header_lines[0].startswith("Format:"):
            issues.append((1, "error",
                "First line must be a Format: field "
                "(e.g. Format: https://www.debian.org/doc/packaging-manuals/"
                "copyright-format/1.0/)", "missing-format"))
        else:
            fmt_url = header_lines[0][7:].strip()
            if "debian.org" not in fmt_url:
                issues.append((1, "warning",
                    f"Format URL looks non-standard: {fmt_url}", None))

        # ── 2. Recommended header fields ─────────────────────────
        hdr_fields = set()
        for hl in header_lines:
            m = re.match(r'^([A-Z][\w-]+):', hl)
            if m:
                hdr_fields.add(m.group(1))
        for rec in ("Upstream-Name", "Upstream-Contact", "Source"):
            if rec not in hdr_fields:
                issues.append((1, "warning",
                    f"Header paragraph missing recommended field: {rec}",
                    None))

    # ── 3. Multiple consecutive blank lines ──────────────────────
    for i, line in enumerate(lines):
        if i > 0 and line == "" and lines[i - 1] == "":
            issues.append((i + 1, "warning",
                "Multiple consecutive blank lines "
                "(paragraphs should be separated by exactly one blank line)",
                "multi-blank"))

    # ── 4. Trailing whitespace ───────────────────────────────────
    for i, line in enumerate(lines):
        if line != line.rstrip():
            issues.append((i + 1, "warning",
                f"Trailing whitespace on line {i + 1}", "trailing-ws"))

    # ── 5. Tab indentation in continuation lines ─────────────────
    for i, line in enumerate(lines):
        if line.startswith("\t"):
            issues.append((i + 1, "error",
                f"Tab indentation on line {i + 1} "
                "(DEP-5 continuation lines must use spaces, not tabs)",
                "tab-indent"))

    # ── 6. Blank continuation lines must be " ." ─────────────────
    in_block = False
    for i, line in enumerate(lines):
        if re.match(r'^[A-Z][\w-]+:', line):
            in_block = True
        elif line == "":
            in_block = False
        elif in_block and line.rstrip() == "" and line != "":
            # Line is all whitespace but not empty — should be " ."
            issues.append((i + 1, "error",
                f"Blank continuation line {i + 1} must be ' .' "
                "(space followed by period), not just whitespace",
                "blank-continuation"))

    # ── 7. File stanzas: required fields ─────────────────────────
    para_line = 1
    for para in paragraphs:
        plines = para.split("\n")
        fields = []
        for pl in plines:
            m = re.match(r'^([A-Z][\w-]+):', pl)
            if m:
                fields.append(m.group(1))

        has_files = "Files" in fields
        has_copyright = "Copyright" in fields
        has_license = "License" in fields

        if has_files:
            if not has_copyright:
                issues.append((para_line, "error",
                    f"Files stanza at line {para_line} missing required "
                    "Copyright: field", None))
            if not has_license:
                issues.append((para_line, "error",
                    f"Files stanza at line {para_line} missing required "
                    "License: field", None))
            # Check field ordering: Files before Copyright before License
            fi = fields.index("Files") if "Files" in fields else -1
            ci = fields.index("Copyright") if "Copyright" in fields else -1
            li = fields.index("License") if "License" in fields else -1
            if ci >= 0 and fi >= 0 and ci < fi:
                issues.append((para_line, "warning",
                    f"Files stanza at line {para_line}: Copyright: should "
                    "come after Files:", "field-order"))
            if li >= 0 and ci >= 0 and li < ci:
                issues.append((para_line, "warning",
                    f"Files stanza at line {para_line}: License: should "
                    "come after Copyright:", "field-order"))

        # Standalone License block must have body
        if has_license and not has_files and not plines[0].startswith("Format:"):
            body_lines = [l for l in plines[1:] if l.startswith(" ") or l == " ."]
            if not body_lines:
                lic_name = plines[0][8:].strip().split()[0] if plines[0][8:].strip() else "?"
                issues.append((para_line, "error",
                    f"Standalone License block '{lic_name}' at line "
                    f"{para_line} has no body text", None))

        # ── 8. Unrecognized fields ───────────────────────────────
        KNOWN_FIELDS = {
            "Format", "Upstream-Name", "Upstream-Contact", "Source",
            "Disclaimer", "Comment", "License", "Copyright", "Files",
            "Files-Excluded", "Files-Excluded-DFSG",
        }
        for pl in plines:
            m = re.match(r'^([A-Z][\w-]+):', pl)
            if m and m.group(1) not in KNOWN_FIELDS:
                lnum = para_line + plines.index(pl)
                issues.append((lnum, "warning",
                    f"Unrecognized field '{m.group(1)}' at line {lnum}",
                    None))

        para_line += len(plines) + 1  # +1 for blank separator

    # ── 9. Catch-all stanza ──────────────────────────────────────
    has_catchall = any(g == "*" for g, _ in stanzas)
    if not has_catchall and stanzas:
        issues.append((0, "warning",
            "No catch-all 'Files: *' stanza found (recommended)", None))

    # ── 10. Duplicate file globs ─────────────────────────────────
    glob_counts = defaultdict(int)
    for g, _ in stanzas:
        glob_counts[g] += 1
    for g, count in glob_counts.items():
        if count > 1:
            issues.append((0, "warning",
                f"File glob '{g}' appears in {count} stanzas "
                "(later stanzas override earlier ones)", None))

    # ── 11. File does not end with newline ────────────────────────
    if raw and not raw.endswith("\n"):
        issues.append((len(lines), "warning",
            "File does not end with a newline", "missing-newline"))

    return issues

def fix_dep5_format(text):
    """Apply automatic DEP-5 format fixes to the copyright text.

    Returns (fixed_text, list_of_fix_descriptions).
    """
    fixes = []

    # Fix trailing whitespace
    new_lines = []
    trailing_fixed = 0
    for line in text.split("\n"):
        stripped = line.rstrip()
        if stripped != line:
            trailing_fixed += 1
        new_lines.append(stripped)
    if trailing_fixed > 0:
        fixes.append(f"Removed trailing whitespace from {trailing_fixed} line(s)")
    text = "\n".join(new_lines)

    # Fix multiple consecutive blank lines
    old_len = len(text)
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    if len(text) != old_len:
        fixes.append("Collapsed multiple consecutive blank lines")

    # Fix tab indentation → spaces
    tab_count = 0
    new_lines = []
    for line in text.split("\n"):
        if line.startswith("\t"):
            line = " " + line.lstrip("\t")
            tab_count += 1
        new_lines.append(line)
    if tab_count > 0:
        fixes.append(f"Replaced tab indentation with spaces on {tab_count} line(s)")
    text = "\n".join(new_lines)

    # Fix blank continuation lines (whitespace-only → " .")
    in_block = False
    new_lines = []
    blank_cont_fixed = 0
    for line in text.split("\n"):
        if re.match(r'^[A-Z][\w-]+:', line):
            in_block = True
            new_lines.append(line)
        elif line == "":
            in_block = False
            new_lines.append(line)
        elif in_block and line.rstrip() == "" and line != "":
            new_lines.append(" .")
            blank_cont_fixed += 1
        else:
            new_lines.append(line)
    if blank_cont_fixed > 0:
        fixes.append(f"Fixed {blank_cont_fixed} blank continuation line(s) → ' .'")
    text = "\n".join(new_lines)

    # Ensure file ends with newline
    if text and not text.endswith("\n"):
        text += "\n"
        fixes.append("Added missing trailing newline")

    return text, fixes

def get_declared_license(filepath):
    fp = filepath.lstrip("./")
    best, best_spec = None, -1
    for glob, lic in stanzas:
        if fnmatch.fnmatch(fp, glob):
            spec = glob.count("/") * 100 + len(glob)
            if spec > best_spec:
                best_spec = spec
                best = lic
    if best is None:
        for glob, lic in stanzas:
            if glob == "*":
                return lic
    return best

# ══════════════════════════════════════════════════════════════════════
# False-positive heuristic
# ══════════════════════════════════════════════════════════════════════
def classify_fp(filepath, detected, declared):
    fp = filepath.lstrip("./")
    if re.search(r'(?:^|/)LICENSE[^/]*\.txt$', fp, re.I):
        return "license-text-file"
    if re.search(r'conftools/|\.m4$|config\.guess$|config\.sub$|ltmain', fp, re.I):
        return "autoconf-boilerplate"
    if fp.endswith(".rst") and detected.lower() in (
            "cecill", "cecill-c", "bsl-1.0", "apache-2.0", "gpl-2"):
        return "doc-embeds-plugin-license"
    if re.search(r'(CMakeLists\.txt|\.pro)$', fp):
        return "project-build-file"
    if fp.startswith("tools/"):
        return "tools-infrastructure"
    return None

def licenses_compatible(detected_raw, declared):
    dn = norm_cmp(declared)
    dn2 = norm_cmp(detected_raw)
    if dn == dn2:
        return True
    # GPL-2+ subsumes GPL-2
    if dn in ("gpl-2+", "gpl-2") and dn2 in ("gpl-2+", "gpl-2", "gpl"):
        return True
    return False

# ══════════════════════════════════════════════════════════════════════
# MODE: generate — build a debian/copyright from scan results
# ══════════════════════════════════════════════════════════════════════
if mode == "generate":
    # Group files by (frozenset(licenses), frozenset(copyrights))
    groups = defaultdict(list)
    for r in scan_results:
        if not r["licenses"]:
            continue
        key = (tuple(sorted(set(to_dep5(l) for l in r["licenses"]))),
               tuple(sorted(set(r["copyrights"]))))
        groups[key].append(r["path"].lstrip("./"))

    # Find the most common license group for the catch-all
    biggest_key = max(groups, key=lambda k: len(groups[k]))

    # Build common-prefix globs for each group
    def make_glob(paths):
        """Produce the shortest set of globs covering all paths."""
        dirs = defaultdict(list)
        for p in paths:
            d = str(Path(p).parent)
            dirs[d].append(p)
        globs = []
        for d, files in sorted(dirs.items()):
            if d == ".":
                globs.extend(files)
            else:
                # If more than half the dir is covered, use dir/*
                globs.append(d + "/*")
        return globs

    out = []
    out.append("Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/")
    out.append("Upstream-Name: FIXME")
    out.append("Upstream-Contact: FIXME")
    out.append("Source: FIXME")
    out.append("")

    # Catch-all stanza
    lics, cops = biggest_key
    out.append("Files: *")
    if cops:
        out.append("Copyright: " + "\n           ".join(cops[:5]))
    else:
        out.append("Copyright: FIXME")
    out.append("License: " + " AND ".join(lics))
    out.append("")

    # Other stanzas (sorted by license then path)
    for key in sorted(groups.keys()):
        if key == biggest_key:
            continue
        lics, cops = key
        paths = sorted(groups[key])
        if len(paths) > 20:
            globs = make_glob(paths)
        else:
            globs = paths

        out.append("Files: " + "\n       ".join(globs))
        if cops:
            out.append("Copyright: " + "\n           ".join(cops[:5]))
        else:
            out.append("Copyright: FIXME")
        out.append("License: " + " AND ".join(lics))
        out.append("")

    # License text stubs
    all_lics = set()
    for (lics, _) in groups:
        all_lics.update(lics)

    # Licenses with full text available in /usr/share/common-licenses/
    COMMON_LICENSES = {
        "GPL-1", "GPL-2", "GPL-2+", "GPL-3", "GPL-3+",
        "LGPL-2", "LGPL-2+", "LGPL-2.1", "LGPL-2.1+", "LGPL-3", "LGPL-3+",
        "Apache-2.0", "MPL-1.1", "MPL-2.0",
        "GFDL", "GFDL-1.2", "GFDL-1.3",
        "Artistic", "BSD", "CC0-1.0",
    }

    # Creative Commons licenses that need the full legal text embedded
    CC_NEEDS_FULL_TEXT = {
        "CC-BY-1.0", "CC-BY-2.0", "CC-BY-2.5", "CC-BY-3.0", "CC-BY-4.0",
        "CC-BY-SA-1.0", "CC-BY-SA-2.0", "CC-BY-SA-2.5", "CC-BY-SA-3.0", "CC-BY-SA-4.0",
        "CC-BY-NC-1.0", "CC-BY-NC-2.0", "CC-BY-NC-2.5", "CC-BY-NC-3.0", "CC-BY-NC-4.0",
        "CC-BY-ND-1.0", "CC-BY-ND-2.0", "CC-BY-ND-2.5", "CC-BY-ND-3.0", "CC-BY-ND-4.0",
        "CC-BY-NC-SA-1.0", "CC-BY-NC-SA-2.0", "CC-BY-NC-SA-2.5", "CC-BY-NC-SA-3.0", "CC-BY-NC-SA-4.0",
        "CC-BY-NC-ND-1.0", "CC-BY-NC-ND-2.0", "CC-BY-NC-ND-2.5", "CC-BY-NC-ND-3.0", "CC-BY-NC-ND-4.0",
    }

    for lic in sorted(all_lics):
        out.append(f"License: {lic}")
        if lic in COMMON_LICENSES:
            slug = lic.rstrip("+")
            out.append(f" On Debian systems, the full text of this license can be found in")
            out.append(f" `/usr/share/common-licenses/{slug}'.")
        elif lic in CC_NEEDS_FULL_TEXT:
            out.append(f" FIXME: Include the FULL legal text of {lic} here.")
            out.append(f" Creative Commons licenses (except CC0-1.0) are NOT in")
            out.append(f" /usr/share/common-licenses/. lintian will flag an incomplete")
            out.append(f" CC license. Download the full text from:")
            tag = lic.lower().replace("cc-", "").rsplit("-", 1)
            variant = tag[0] if tag else lic.lower()
            version = tag[1] if len(tag) > 1 else "4.0"
            out.append(f" https://creativecommons.org/licenses/{variant}/{version}/legalcode.txt")
        else:
            out.append(" FIXME: Add the full license text here.")
            out.append(" This license is not in /usr/share/common-licenses/.")
        out.append("")

    result = "\n".join(out)
    if output_file:
        with open(output_file, "w") as f:
            f.write(result)
        print(f"Generated copyright written to: {output_file}", file=sys.stderr)
    else:
        print(result)

    # Summary to stderr
    print(f"\n  Files scanned:  {len(scan_results)}", file=sys.stderr)
    print(f"  License groups: {len(groups)}", file=sys.stderr)
    print(f"  Unique licenses: {len(all_lics)}", file=sys.stderr)
    print(f"  Stanzas (excl. catch-all): {len(groups) - 1}", file=sys.stderr)
    print(f"\n  Review the output carefully — FIXME markers need attention.", file=sys.stderr)
    sys.exit(0)

# ══════════════════════════════════════════════════════════════════════
# MODE: check / review — validate existing debian/copyright
# ══════════════════════════════════════════════════════════════════════
NONFREE = {"agpl-3.0-only", "agpl-3", "cecill", "cecill-c", "sspl-1.0"}

real_mismatches = defaultdict(list)
fp_mismatches = defaultdict(list)
no_license = []
apache_files = []
all_scan_licenses = defaultdict(int)

for r in scan_results:
    fp = r["path"]
    if not r["licenses"]:
        no_license.append(fp)
        continue

    for raw_lic in r["licenses"]:
        dep5 = to_dep5(raw_lic)
        all_scan_licenses[dep5] += 1
        declared = get_declared_license(fp)
        if not declared:
            declared = "GPL-2+"

        if "apache" in raw_lic.lower():
            apache_files.append(fp)

        if licenses_compatible(raw_lic, declared):
            continue

        category = classify_fp(fp, raw_lic, declared)
        if category:
            fp_mismatches[category].append((fp, dep5, declared))
        else:
            real_mismatches[(dep5, declared)].append(fp)

W = 70
real_count = sum(len(v) for v in real_mismatches.values())
fp_count = sum(len(v) for v in fp_mismatches.values())

if mode == "review":
    # ── Reviewer report ───────────────────────────────────────────────
    print("=" * W)
    print("DEBIAN COPYRIGHT REVIEW REPORT")
    print("=" * W)
    print(f"  Scanner: {scanner}" +
          (" (SPDX database)" if scanner == "scancode" else " (heuristic)"))
    print(f"  Files scanned: {len(scan_results)}")
    print(f"  File stanzas in debian/copyright: {len(stanzas)}")
    print()

    # Test 1: DEP-5 format validation
    dep5_issues = check_dep5_format()
    dep5_errors = [i for i in dep5_issues if i[1] == "error"]
    dep5_warnings = [i for i in dep5_issues if i[1] == "warning"]
    if not dep5_issues:
        print("[PASS] DEP-5 format validation: no issues")
    elif dep5_errors:
        print(f"[FAIL] DEP-5 format validation: {len(dep5_errors)} error(s), "
              f"{len(dep5_warnings)} warning(s)")
        for lnum, sev, msg, _ in dep5_issues:
            prefix = f"Line {lnum}: " if lnum > 0 else ""
            print(f"        [{sev.upper()}] {prefix}{msg}")
    else:
        print(f"[WARN] DEP-5 format validation: {len(dep5_warnings)} warning(s)")
        for lnum, sev, msg, _ in dep5_issues:
            prefix = f"Line {lnum}: " if lnum > 0 else ""
            print(f"        [{sev.upper()}] {prefix}{msg}")

    # Test 2: Catch-all stanza
    has_catchall = any(g == "*" for g, _ in stanzas)
    status = "PASS" if has_catchall else "FAIL"
    print(f"[{status}] Catch-all Files: * stanza")

    # Test 3: Mismatches
    status = "PASS" if real_count == 0 else "WARN" if real_count < 10 else "FAIL"
    print(f"[{status}] License mismatches: {real_count}")

    # Test 4: Missing licenses
    declared_lics = set(lic for _, lic in stanzas)
    missing_in_copyright = set()
    for dep5, count in all_scan_licenses.items():
        if count >= 3:
            found = False
            for _, decl in stanzas:
                if norm_cmp(dep5) == norm_cmp(decl):
                    found = True
                    break
            if not found:
                missing_in_copyright.add(dep5)
    status = "PASS" if not missing_in_copyright else "WARN"
    print(f"[{status}] Undeclared licenses: {len(missing_in_copyright)}")
    for ml in sorted(missing_in_copyright):
        print(f"        {ml} (found in {all_scan_licenses[ml]} files)")

    # Test 5: License compatibility
    has_gpl2plus = any(l == "GPL-2+" for l in declared_lics)
    has_gpl2_only = any(l == "GPL-2" for l in declared_lics)
    has_apache = any("apache" in l.lower() for l in declared_lics)
    if has_apache and has_gpl2_only:
        print("[FAIL] Apache-2.0 + GPL-2 (only) conflict!")
    elif has_apache and has_gpl2plus:
        print("[PASS] Apache-2.0 + GPL-2+ => effective GPL-3+ (compatible)")
    else:
        print("[PASS] No license compatibility issues")

    # Test 6: Non-free
    nonfree_found = []
    for dep5, count in all_scan_licenses.items():
        if norm_cmp(dep5) in NONFREE:
            nonfree_found.append(dep5)
    status = "PASS" if not nonfree_found else "WARN"
    print(f"[{status}] Non-free licenses in source: {len(nonfree_found)}")
    for nf in nonfree_found:
        print(f"        {nf}")

    # Test 7: Files with no license
    source_exts = {".cpp", ".c", ".h", ".hpp", ".py", ".sh", ".pl",
                   ".java", ".js", ".ts", ".rs", ".go"}
    src_no_lic = [f for f in no_license if Path(f).suffix.lower() in source_exts]
    status = "PASS" if len(src_no_lic) == 0 else "INFO"
    print(f"[{status}] Source files without license header: {len(src_no_lic)}")

    # Test 8: License text completeness
    lic_issues = check_license_completeness()
    errors = [i for i in lic_issues if i[1] == "error"]
    warnings = [i for i in lic_issues if i[1] == "warning"]
    if not lic_issues:
        print("[PASS] License text blocks are complete")
    elif errors:
        print(f"[FAIL] License text completeness: {len(errors)} error(s), {len(warnings)} warning(s)")
        for lic, sev, msg in lic_issues:
            print(f"        [{sev.upper()}] {msg}")
    else:
        print(f"[WARN] License text completeness: {len(warnings)} warning(s)")
        for lic, sev, msg in lic_issues:
            print(f"        [{sev.upper()}] {msg}")

    # Test 9: Stanza coverage — uncovered files
    uncovered, stale = check_coverage()
    # Only flag source files as uncovered (data files are fine under catch-all)
    source_exts2 = {".cpp", ".c", ".h", ".hpp", ".py", ".sh", ".pl",
                    ".java", ".js", ".ts", ".rs", ".go", ".cc", ".cxx",
                    ".hxx", ".m", ".mm", ".swift", ".rb"}
    src_uncovered = [(fp, lics) for fp, lics in uncovered
                     if Path(fp).suffix.lower() in source_exts2]
    status = "PASS" if len(src_uncovered) == 0 else (
        "INFO" if len(src_uncovered) < 5 else "WARN")
    print(f"[{status}] Source files not matched by any stanza: {len(src_uncovered)}")
    if src_uncovered:
        for fp, lics in src_uncovered[:5]:
            lic_str = ", ".join(lics) if lics else "(unknown)"
            print(f"        {fp}  [{lic_str}]")
        if len(src_uncovered) > 5:
            print(f"        ... and {len(src_uncovered) - 5} more")

    # Test 10: Stale stanza globs
    status = "PASS" if not stale else "WARN"
    print(f"[{status}] Stale stanza globs (match no file): {len(stale)}")
    for glob_pat, lic in stale[:5]:
        print(f"        {glob_pat}  ({lic})")
    if len(stale) > 5:
        print(f"        ... and {len(stale) - 5} more")

    print()
    lic_ok = not lic_issues or not errors
    cov_ok = len(src_uncovered) == 0
    dep5_ok = not dep5_errors
    if (real_count == 0 and not missing_in_copyright and not nonfree_found
            and lic_ok and cov_ok and not stale and dep5_ok):
        print("VERDICT: debian/copyright appears complete and accurate.")
    elif real_count < 10 and not nonfree_found and dep5_ok:
        print("VERDICT: Minor issues — mostly acceptable, review flagged items.")
    else:
        print("VERDICT: Needs work — review mismatches and missing licenses above.")
    print()

    if real_mismatches:
        print("-" * W)
        print("DETAILED MISMATCHES:")
        print("-" * W)
        for (det, decl), files in sorted(real_mismatches.items()):
            print(f"\n  Detected: {det}")
            print(f"  Declared: {decl}")
            for fp in files[:5]:
                print(f"    -> {fp}")
            if len(files) > 5:
                print(f"    ... and {len(files) - 5} more")
        print()

else:
    # ── Standard check report ─────────────────────────────────────────

    # Run DEP-5 format validation
    dep5_issues = check_dep5_format()
    dep5_errors = [i for i in dep5_issues if i[1] == "error"]
    dep5_warnings = [i for i in dep5_issues if i[1] == "warning"]

    print("=" * W)
    print("SECTION 0: DEP-5 FORMAT VALIDATION")
    print("Structural compliance with machine-readable copyright format")
    print("=" * W)

    if dep5_issues:
        print(f"\n{len(dep5_issues)} format issue(s) found "
              f"({len(dep5_errors)} error(s), {len(dep5_warnings)} warning(s)):\n")
        for lnum, sev, msg, fix_tag in dep5_issues:
            fixable = " [auto-fixable]" if fix_tag else ""
            if lnum > 0:
                print(f"  [{sev.upper()}] Line {lnum}: {msg}{fixable}")
            else:
                print(f"  [{sev.upper()}] {msg}{fixable}")
        print()
    else:
        print("\nDEP-5 format looks correct.\n")

    print("=" * W)
    print("SECTION 1: LICENSE MISMATCHES — NEEDS REVIEW")
    print("Files whose detected license may not match debian/copyright")
    print("=" * W)

    if real_mismatches:
        print(f"\n{real_count} file(s) with mismatched licenses:\n")
        for (det, decl), files in sorted(real_mismatches.items()):
            print(f"  Detected: {det}")
            print(f"  Declared: {decl}")
            for fp in files[:5]:
                print(f"    -> {fp}")
            if len(files) > 5:
                print(f"    ... and {len(files) - 5} more")
            print()
    else:
        print("\nNo actionable mismatches found. debian/copyright looks good!\n")

    FP_LABELS = {
        "license-text-file":
            "LICENSE text files (informational, not compiled code)",
        "autoconf-boilerplate":
            "Autoconf / build-system boilerplate (standard exceptions apply)",
        "doc-embeds-plugin-license":
            "Documentation .rst files embedding upstream plugin license text",
        "project-build-file":
            "Project build files (CMakeLists.txt / .pro) carrying main license",
        "tools-infrastructure":
            "Build infrastructure / tooling files in tools/",
    }

    print("=" * W)
    print("SECTION 2: LIKELY FALSE POSITIVES (informational)")
    print("=" * W)

    if fp_mismatches:
        print(f"\n{fp_count} file(s) classified as likely false positives:\n")
        for cat in sorted(fp_mismatches):
            items = fp_mismatches[cat]
            label = FP_LABELS.get(cat, cat)
            print(f"  [{len(items)}] {label}")
            if verbose:
                for fp, det, decl in items[:5]:
                    print(f"       {fp}  ({det} vs {decl})")
                if len(items) > 5:
                    print(f"       ... and {len(items) - 5} more")
        print()
        if not verbose:
            print("  (Use --verbose to see individual files)\n")
    else:
        print("\nNone.\n")

    print("=" * W)
    print("SECTION 3: LICENSE TEXT COMPLETENESS")
    print("=" * W)

    lic_issues = check_license_completeness()
    if lic_issues:
        errors = [i for i in lic_issues if i[1] == "error"]
        warnings = [i for i in lic_issues if i[1] == "warning"]
        print(f"\n{len(lic_issues)} issue(s) with license text blocks:\n")
        for lic, sev, msg in lic_issues:
            print(f"  [{sev.upper()}] {msg}")
        print()
        print("  Tip: licenses not in /usr/share/common-licenses/ must have their")
        print("  full legal text included in debian/copyright. Creative Commons")
        print("  licenses (except CC0-1.0) must include the complete legal code,")
        print("  not just a summary — lintian checks for this specifically.")
    else:
        print("\nAll license text blocks appear complete.")
    print()

    print("=" * W)
    print("SECTION 4: LICENSE COMPATIBILITY")
    print("=" * W)

    all_declared = set(lic for _, lic in stanzas)
    has_gpl2_only = any(l == "GPL-2" for l in all_declared)
    has_gpl2plus = any(l == "GPL-2+" for l in all_declared)
    has_apache = any("apache" in l.lower() for l in all_declared)

    if has_apache and has_gpl2plus and not has_gpl2_only:
        print("""
NOTE: Apache-2.0 files are present alongside GPL-2+ code.
  Apache-2.0 is incompatible with GPL-2-only but compatible with GPL-3+.
  Since the main code is GPL-2+ (version 2 "or later"), the effective
  license of the compiled binary is GPL-3+. This is fine for Debian.
  Apache-2.0 files:""")
        for fp in apache_files[:10]:
            print(f"    {fp}")
        if len(apache_files) > 10:
            print(f"    ... and {len(apache_files) - 10} more")
        print()
    elif has_apache and has_gpl2_only:
        print("""
WARNING: Apache-2.0 files detected with GPL-2-only code!
  Apache-2.0 is INCOMPATIBLE with GPL-2 (without the "or later" clause).
  This is a real license conflict that must be resolved.
""")
    else:
        print("\nNo compatibility issues detected.\n")

    nonfree_found = []
    for (det, _), files in real_mismatches.items():
        if norm_cmp(det) in NONFREE:
            nonfree_found.extend(files)
    if nonfree_found:
        print("WARNING: Potentially non-free licensed files detected:")
        for fp in nonfree_found[:10]:
            print(f"    {fp}")
        print()

    print("=" * W)
    print("SECTION 5: LICENSES FOUND IN SOURCE (detected by scanner)")
    print("=" * W)
    print()
    for lic, count in sorted(all_scan_licenses.items(), key=lambda x: -x[1]):
        declared_match = any(norm_cmp(lic) == norm_cmp(d) for _, d in stanzas)
        marker = " " if declared_match else "!"
        print(f"  {marker} {lic:30s} {count:5d} file(s)"
              + ("" if declared_match else "  <-- NOT in debian/copyright"))
    print()

    print("=" * W)
    print("SECTION 6: STANZA COVERAGE ANALYSIS")
    print("=" * W)

    uncovered, stale = check_coverage()
    source_exts2 = {".cpp", ".c", ".h", ".hpp", ".py", ".sh", ".pl",
                    ".java", ".js", ".ts", ".rs", ".go", ".cc", ".cxx",
                    ".hxx", ".m", ".mm", ".swift", ".rb"}
    src_uncovered = [(fp, lics) for fp, lics in uncovered
                     if Path(fp).suffix.lower() in source_exts2]
    data_uncovered = [(fp, lics) for fp, lics in uncovered
                      if Path(fp).suffix.lower() not in source_exts2]

    if src_uncovered:
        print(f"\n{len(src_uncovered)} source file(s) not matched by any Files: stanza:")
        print("  (These are only covered by the catch-all * glob)\n")
        for fp, lics in src_uncovered[:20]:
            lic_str = ", ".join(lics) if lics else "(no license detected)"
            print(f"    {fp}")
            print(f"      detected: {lic_str}")
        if len(src_uncovered) > 20:
            print(f"    ... and {len(src_uncovered) - 20} more")
        print()
    else:
        print("\nAll source files are matched by a specific Files: stanza.")
        print()

    if data_uncovered:
        print(f"  ({len(data_uncovered)} non-source files also only matched by catch-all,")
        print(f"   which is normal for data files, images, configs, etc.)")
        if verbose:
            for fp, lics in data_uncovered[:10]:
                lic_str = ", ".join(lics) if lics else "(none)"
                print(f"    {fp}  [{lic_str}]")
            if len(data_uncovered) > 10:
                print(f"    ... and {len(data_uncovered) - 10} more")
        print()

    if stale:
        print(f"{len(stale)} Files: glob(s) in debian/copyright match no actual file:")
        print("  (These may be stale entries from removed/renamed files)\n")
        for glob_pat, lic in stale:
            print(f"    {glob_pat}  (License: {lic})")
        print()
    elif stanzas:
        print("All Files: globs match at least one file in the source tree.")
        print()

    print("=" * W)
    print("SECTION 7: FILES WITH NO DETECTED LICENSE")
    print("=" * W)

    if no_license:
        source_exts = {".cpp", ".c", ".h", ".hpp", ".py", ".sh", ".pl",
                       ".java", ".js", ".ts", ".rs", ".go"}
        src_no_lic = [f for f in no_license
                      if Path(f).suffix.lower() in source_exts]
        if src_no_lic:
            print(f"\n{len(src_no_lic)} source file(s) with no license header:")
            for fp in src_no_lic[:20]:
                print(f"    {fp}")
            if len(src_no_lic) > 20:
                print(f"    ... and {len(src_no_lic) - 20} more")
        else:
            print(f"\n{len(no_license)} file(s) with no license header"
                  " (all non-source).")
        print(f"  Total files without detected license: {len(no_license)}")
        print("  (Data files, images, configs, etc. are typically fine"
              " without headers)")
    else:
        print("\nAll files have detectable license headers.")
    print()

    # Summary
    print("=" * W)
    print("SUMMARY")
    print("=" * W)
    print(f"  Scanner:                               {scanner}"
          + (" (SPDX)" if scanner == "scancode" else " (heuristic)"))
    print(f"  Files scanned:                         {len(scan_results)}")
    print(f"  Unique licenses detected:              {len(all_scan_licenses)}")
    print(f"  Licenses declared in debian/copyright: {len(all_declared)}")
    print(f"  File stanzas in debian/copyright:      {len(stanzas)}")
    print(f"  Mismatches needing review:             {real_count}")
    print(f"  Likely false positives:                {fp_count}")
    print(f"  Files with no license header:          {len(no_license)}")
    print(f"  Source files uncovered by stanzas:     {len(src_uncovered)}")
    print(f"  Stale stanza globs:                    {len(stale)}")
    print(f"  DEP-5 format errors:                   {len(dep5_errors)}")
    print(f"  DEP-5 format warnings:                 {len(dep5_warnings)}")

    total_issues = real_count + len(src_uncovered) + len(stale) + len(dep5_errors)
    if total_issues == 0:
        print("\n  RESULT: debian/copyright appears complete.")
    else:
        print(f"\n  RESULT: {total_issues} item(s) may need attention.")
    print()

    # ══════════════════════════════════════════════════════════════════
    # Interactive fix mode
    # ══════════════════════════════════════════════════════════════════
    fixable_dep5_count = sum(1 for i in dep5_issues if i[3] is not None)
    if fix_mode and (total_issues > 0 or fixable_dep5_count > 0) and copyright_file:
        print("=" * W)
        print("INTERACTIVE FIX MODE")
        print("=" * W)
        print()

        # input() won't work — stdin is the heredoc.
        # Read interactive answers from /dev/tty instead.
        try:
            _tty = open("/dev/tty", "r")
        except OSError:
            print("ERROR: Cannot open /dev/tty for interactive input.", file=sys.stderr)
            print("  --fix requires an interactive terminal.", file=sys.stderr)
            sys.exit(1)

        # Force unbuffered output so prompts appear immediately
        import functools
        print = functools.partial(print, flush=True)

        def ask(prompt):
            """Prompt the user and read from /dev/tty."""
            if yes_mode:
                sys.stdout.write(prompt + "y (--yes)\n")
                sys.stdout.flush()
                return "y"
            sys.stdout.write(prompt)
            sys.stdout.flush()
            try:
                return _tty.readline().rstrip("\n")
            except EOFError:
                return ""

        # Read the current copyright file
        with open(copyright_file) as f:
            original_text = f.read()
        working_text = original_text
        changes_made = 0

        # Helper: build compact globs from a list of file paths
        def make_fix_globs(paths):
            """Group files by directory and produce compact globs."""
            dirs = defaultdict(list)
            for p in paths:
                p = p.lstrip("./")
                d = str(Path(p).parent)
                dirs[d].append(p)
            globs = []
            for d, files in sorted(dirs.items()):
                if d == ".":
                    globs.extend(files)
                else:
                    globs.append(d + "/*")
            return globs

        # Helper: find the copyright holders for a set of files from scan
        def get_copyrights_for_files(filepaths):
            cops = set()
            fp_set = set(filepaths)
            for r in scan_results:
                if r["path"] in fp_set or r["path"].lstrip("./") in fp_set:
                    for c in r.get("copyrights", []):
                        if c:
                            cops.add(c)
            return sorted(cops)

        # Helper: find insertion point (before the first standalone License: block)
        def find_stanza_insert_pos(text):
            """Find the byte offset to insert new File stanzas.
            Inserts before the first standalone License: paragraph."""
            best_pos = len(text)  # default: end of file
            for m in re.finditer(r'\n\nLicense: ', text):
                # Check this is standalone (no Files: in this paragraph)
                para_start = m.start() + 2
                para_end = text.find("\n\n", para_start)
                if para_end == -1:
                    para_end = len(text)
                para = text[para_start:para_end]
                if not para.startswith("Files:") and "\nFiles:" not in para:
                    best_pos = m.start() + 1  # after the first \n
                    break
            return best_pos

        # ── Fix 0: DEP-5 format fixes ───────────────────────────────
        fixable_dep5 = [i for i in dep5_issues if i[3] is not None]
        if fixable_dep5:
            print(f"{len(fixable_dep5)} auto-fixable DEP-5 format issue(s):\n")
            for lnum, sev, msg, fix_tag in fixable_dep5:
                prefix = f"Line {lnum}: " if lnum > 0 else ""
                print(f"  [{sev.upper()}] {prefix}{msg}")

            answer = ask("\n  Apply DEP-5 format fixes? [y/N] ").strip().lower()
            if answer in ("y", "yes"):
                working_text, fix_descs = fix_dep5_format(working_text)
                for desc in fix_descs:
                    print(f"  ✓ {desc}")
                changes_made += 1
                print()
            else:
                print("  ✗ Skipped.\n")

        # ── Fix 1: Add stanzas for mismatched files ──────────────────
        if real_mismatches:
            # Group mismatched files by detected license
            by_license = defaultdict(list)
            for (det, decl), files in real_mismatches.items():
                # Skip debian/copyright itself (it embeds many license texts)
                filtered = [f for f in files
                            if f.lstrip("./") != "debian/copyright"]
                if filtered:
                    by_license[det].extend(filtered)

            if by_license:
                print("The following new Files: stanzas are proposed for")
                print("files whose detected license differs from what's declared:\n")

            for det_lic, files in sorted(by_license.items()):
                globs = make_fix_globs(files)
                cops = get_copyrights_for_files(files)
                cop_str = cops[0] if cops else "FIXME"

                print(f"  Proposed stanza ({len(files)} file(s)):")
                print(f"  ┌──────────────────────────────────────")
                if len(globs) <= 3:
                    print(f"  │ Files: {globs[0]}")
                    for g in globs[1:]:
                        print(f"  │        {g}")
                else:
                    print(f"  │ Files: {globs[0]}")
                    print(f"  │        {globs[1]}")
                    print(f"  │        ... ({len(globs)} globs total)")
                print(f"  │ Copyright: {cop_str}")
                print(f"  │ License: {det_lic}")
                print(f"  └──────────────────────────────────────")

                answer = ask("  Add this stanza? [y/N/e(dit)] ").strip().lower()

                if answer in ("y", "yes"):
                    # Build the stanza text
                    file_lines = "\n       ".join(globs)
                    stanza = f"\nFiles: {file_lines}\nCopyright: {cop_str}\nLicense: {det_lic}\n"
                    pos = find_stanza_insert_pos(working_text)
                    working_text = working_text[:pos] + stanza + working_text[pos:]
                    changes_made += 1
                    print(f"  ✓ Added.\n")
                elif answer in ("e", "edit"):
                    print(f"  Enter copyright holder (or press Enter for '{cop_str}'):")
                    new_cop = ask("    Copyright: ").strip()
                    if not new_cop:
                        new_cop = cop_str
                    print(f"  Enter license (or press Enter for '{det_lic}'):")
                    new_lic = ask("    License: ").strip()
                    if not new_lic:
                        new_lic = det_lic
                    file_lines = "\n       ".join(globs)
                    stanza = f"\nFiles: {file_lines}\nCopyright: {new_cop}\nLicense: {new_lic}\n"
                    pos = find_stanza_insert_pos(working_text)
                    working_text = working_text[:pos] + stanza + working_text[pos:]
                    changes_made += 1
                    print(f"  ✓ Added (edited).\n")
                else:
                    print(f"  ✗ Skipped.\n")

        # ── Fix 2: Remove stale globs ────────────────────────────────
        if stale:
            print(f"{len(stale)} stale glob(s) found that match no file:\n")
            for glob_pat, lic in stale:
                print(f"  Stale: {glob_pat}  (License: {lic})")
            answer = ask("\n  Remove all stale globs? [y/N] ").strip().lower()
            if answer in ("y", "yes"):
                for glob_pat, lic in stale:
                    # Remove the glob from its Files: line
                    # Pattern: the glob on its own line with leading spaces, or on the Files: line
                    escaped = re.escape(glob_pat)
                    # Try removing from continuation line
                    working_text = re.sub(
                        r'\n       ' + escaped + r'(?=\n)', '', working_text)
                    # Try removing from Files: line (if it's the only entry)
                    working_text = re.sub(
                        r'Files: ' + escaped + r'\n', 'Files: ', working_text)
                changes_made += 1
                print("  ✓ Removed.\n")
            else:
                print("  ✗ Skipped.\n")

        # ── Fix 3: Add missing license text blocks ───────────────────
        # Check if any new licenses were introduced that lack a text block
        new_lics_in_text = set()
        for m in re.finditer(r'^License: (\S+)', working_text, re.MULTILINE):
            new_lics_in_text.add(m.group(1))

        # Licenses that appear in Files stanzas but have no standalone block
        existing_blocks = set()
        for para in working_text.split("\n\n"):
            lines = para.strip().split("\n")
            if not lines:
                continue
            first = lines[0]
            has_files = any(l.strip().startswith("Files:") for l in lines)
            if first.startswith("License:") and not has_files:
                lic_name = first[8:].strip().split()[0] if first[8:].strip() else None
                if lic_name:
                    existing_blocks.add(lic_name)

        # Collect licenses used in file stanzas
        stanza_lics = set()
        for para in working_text.split("\n\n"):
            lines = para.strip().split("\n")
            has_files = any(l.strip().startswith("Files:") for l in lines)
            if has_files:
                for l in lines:
                    if l.startswith("License:"):
                        lic = l[8:].strip().split()[0] if l[8:].strip() else None
                        if lic:
                            stanza_lics.add(lic)

        missing_blocks = stanza_lics - existing_blocks

        COMMON_LICENSES = {
            "GPL-1", "GPL-2", "GPL-2+", "GPL-3", "GPL-3+",
            "LGPL-2", "LGPL-2+", "LGPL-2.1", "LGPL-2.1+", "LGPL-3", "LGPL-3+",
            "Apache-2.0", "MPL-1.1", "MPL-2.0",
            "GFDL", "GFDL-1.2", "GFDL-1.3",
            "Artistic", "BSD", "CC0-1.0",
        }

        if missing_blocks:
            print(f"{len(missing_blocks)} license(s) need a License text block:\n")
            for lic in sorted(missing_blocks):
                slug = lic.rstrip("+")
                if slug in SYSTEM_COMMON_LICENSES or lic in COMMON_LICENSES:
                    block = (f"\nLicense: {lic}\n"
                             f" On Debian systems, the full text of this license can be found in\n"
                             f" `/usr/share/common-licenses/{slug}'.\n")
                    print(f"  {lic} → will reference /usr/share/common-licenses/{slug}")
                else:
                    block = (f"\nLicense: {lic}\n"
                             f" FIXME: Add the full license text here.\n")
                    print(f"  {lic} → FIXME stub (you must add the full text)")

                answer = ask(f"  Add License block for {lic}? [y/N] ").strip().lower()
                if answer in ("y", "yes"):
                    working_text = working_text.rstrip("\n") + "\n" + block
                    changes_made += 1
                    print(f"  ✓ Added.\n")
                else:
                    print(f"  ✗ Skipped.\n")

        # ── Write result ─────────────────────────────────────────────
        if changes_made > 0:
            # Clean up any double-blank-lines introduced
            while "\n\n\n" in working_text:
                working_text = working_text.replace("\n\n\n", "\n\n")
            working_text = working_text.rstrip("\n") + "\n"

            print(f"\n{changes_made} fix(es) ready to apply.")
            answer = ask(f"Write changes to {copyright_file}? [y/N] ").strip().lower()
            if answer in ("y", "yes"):
                # Write backup
                backup = copyright_file + ".bak"
                with open(backup, "w") as f:
                    f.write(original_text)
                with open(copyright_file, "w") as f:
                    f.write(working_text)
                print(f"\n  ✓ Written to {copyright_file}")
                print(f"  ✓ Backup saved to {backup}")
            else:
                # Offer to write to a different file
                alt = ask("  Write to alternate file instead? [path or Enter to discard] ").strip()
                if alt:
                    with open(alt, "w") as f:
                        f.write(working_text)
                    print(f"  ✓ Written to {alt}")
                else:
                    print("  Changes discarded.")
        else:
            print("No fixes applied.")
        print()
PYEOF

echo "Done." >&2
