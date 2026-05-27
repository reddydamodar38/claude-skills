#!/usr/bin/env python3
import argparse
import bisect
import json
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any


ANSI_RE = re.compile(r"\x1B\[[0-9;]*[A-Za-z]")
TX_BRACKET_RE = re.compile(r"\[(\d+)\]\s+\[([^\]]+)\]")
REQ_JSON_RE = re.compile(r'(?i)"requestName"\s*:\s*"([^"]+)"')
TOKEN_RE = re.compile(r"\$\{([^}]+)\}")
FAIL_BUILD_RE = re.compile(r"(?i)Failed to build request")
FAIL_BUILD_STORED_RE = re.compile(r"(?i)does not exist in the stored response values")
KW_FAILURE_RE = re.compile(
    r"(?i)(Request failed, reply body|Failed to build request|had the status:\s*F|GeneralDomainCallException)"
)


def eprint(msg: str) -> None:
    print(msg, flush=True)


def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)


def truncate_text(s: str, max_len: int = 2000) -> str:
    if not s:
        return ""
    return s if len(s) <= max_len else s[:max_len] + "...(truncated)"


def extract_json_object(text: str) -> Optional[str]:
    if not text:
        return None
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for i in range(start, len(text)):
        ch = text[i]
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if not in_string:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start : i + 1]
    return None


def try_pretty_json(text: str) -> Optional[str]:
    if not text:
        return None
    candidate = text.strip().replace("&quot;", '"').replace("&amp;", "&")
    candidate = candidate.replace("\\r\\n", "\n").replace("\\n", "\n")
    raw = extract_json_object(candidate)
    if not raw:
        return None
    try:
        obj = json.loads(raw)
        return json.dumps(obj, indent=2, ensure_ascii=False)
    except Exception:
        # Keep a complete JSON object even when strict parsing fails (for very large/wrapped logs).
        return raw


def try_pretty_json_from_lines(lines: List[str], start_idx: int, max_lookahead: int = 1200) -> Optional[str]:
    if start_idx < 0 or start_idx >= len(lines):
        return None
    line = lines[start_idx]
    start = line.find("{")
    if start < 0:
        return None
    buf: List[str] = []
    depth = 0
    in_string = False
    escaped = False
    started = False
    last = min(len(lines) - 1, start_idx + max_lookahead)
    for i in range(start_idx, last + 1):
        seg = lines[i][start:] if i == start_idx else lines[i]
        buf.append(seg)
        for ch in seg:
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == '"':
                in_string = not in_string
                continue
            if not in_string:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
                    if started and depth == 0:
                        return try_pretty_json("\n".join(buf))
    # Fallback for very large/wrapped log payloads: consume until next timestamped log line.
    boundary = try_json_block_until_log_boundary(lines, start_idx, max_lookahead)
    if boundary:
        return try_pretty_json(boundary) or boundary
    return None


def try_json_block_until_log_boundary(lines: List[str], start_idx: int, max_lookahead: int = 1200) -> Optional[str]:
    if start_idx < 0 or start_idx >= len(lines):
        return None
    first = lines[start_idx]
    start = first.find("{")
    if start < 0:
        return None
    ts_re = re.compile(r"^\d{2}:\d{2}:\d{2}\.\d{3}\s+\[")
    last = min(len(lines) - 1, start_idx + max_lookahead)
    parts: List[str] = []
    parts.append(first[start:])
    for i in range(start_idx + 1, last + 1):
        ln = lines[i]
        if ts_re.match(ln):
            break
        parts.append(ln)
    joined = "\n".join(parts).strip()
    if not joined:
        return None
    raw = extract_json_object(joined)
    return raw if raw else joined


def parse_request_name(pretty_json: Optional[str]) -> Optional[str]:
    if not pretty_json:
        return None
    m = REQ_JSON_RE.search(pretty_json)
    return m.group(1) if m else None


def parse_requests_and_errors(report_lines: List[str]) -> Tuple[List[Dict[str, str]], List[str]]:
    summary_rows: List[Dict[str, str]] = []
    seen = set()
    all_tx = set()

    def add_row(tx: str, outcome: str, source: str) -> None:
        tx = (tx or "").strip()
        outcome = (outcome or "").strip()
        if not tx or not outcome:
            return
        key = f"{source}|{tx}|{outcome}"
        if key in seen:
            return
        seen.add(key)
        summary_rows.append({"Transaction": tx, "Outcome": outcome, "Source": source})

    in_requests = False
    req_re = re.compile(r"^\s*>\s*(.+?)\s+\(OK=\s*(\d+)\s+KO=\s*(\d+)\s*\)")
    for line in report_lines:
        if re.match(r"^\s*----\s+Requests\s+", line):
            in_requests = True
            continue
        if in_requests and re.match(r"^\s*----\s+", line) and not re.match(r"^\s*----\s+Requests\s+", line):
            in_requests = False
            continue
        if not in_requests:
            continue
        m = req_re.match(line)
        if not m:
            continue
        tx = m.group(1).strip()
        ko = int(m.group(3))
        if tx and tx != "Global":
            all_tx.add(tx)
        if ko > 0 and tx != "Global":
            add_row(tx, f"KO={ko}", "KO")

    in_errors = False
    cur: List[str] = []
    entries: List[str] = []
    for line in report_lines:
        if re.match(r"^\s*----\s+Errors\s+", line):
            in_errors = True
            continue
        if in_errors and re.match(r"^\s*----\s+", line):
            if cur:
                entries.append(" ".join(cur).strip())
                cur = []
            in_errors = False
            continue
        if not in_errors:
            continue
        if re.match(r"^\s*>\s*", line):
            if cur:
                entries.append(" ".join(cur).strip())
            cur = [re.sub(r"^\s*>\s*", "", line).strip()]
        elif cur:
            cur.append(line.strip())
    if cur:
        entries.append(" ".join(cur).strip())

    count_any = re.compile(r"^(?P<before>.*?)\s+(?P<count>\d+)\s+\(\s*(?P<pct>[\d.]+%)\s*\)\s*(?P<after>.*)$")
    split_re = re.compile(r"^([^:]+):\s*(.+)$")
    for entry in entries:
        flat = re.sub(r"\s+", " ", entry).strip()
        m = count_any.match(flat)
        content = f"{m.group('before')} {m.group('after')}".strip() if m else flat
        content = re.sub(r"\s+", " ", content).strip()
        sm = split_re.match(content)
        if not sm:
            continue
        tx = sm.group(1).strip()
        msg = sm.group(2).strip()
        if "(" in tx or ")" in tx or not re.match(r"^[A-Za-z0-9_-]+$", tx):
            continue
        if re.search(r"(?i)failed to build request", msg):
            msg = "Failed to build request"
        add_row(tx, msg, "ERROR")
    return summary_rows, sorted(all_tx)


def resolve_replies_paths(scenario_dir: str) -> List[str]:
    root = Path(scenario_dir)
    if not root.exists():
        return []
    files = [p for p in root.rglob("*") if p.is_file() and re.match(r"(?i)^replies.*\.yaml$", p.name)]
    if not files:
        return []
    preferred = [p for p in files if re.search(r"(?i)[\\/](Results)[\\/]", str(p))]
    target = preferred if preferred else files
    target.sort(key=lambda p: (p.name.lower(), -int(p.stat().st_mtime)))
    return [str(p) for p in target]


def remove_common_indent(text: str) -> str:
    if not text.strip():
        return ""
    lines = text.splitlines()
    non_empty = [ln for ln in lines if ln.strip()]
    min_indent = min(len(re.match(r"^\s*", ln).group(0)) for ln in non_empty) if non_empty else 0
    return "\n".join(ln[min_indent:] if len(ln) >= min_indent else ln.lstrip() for ln in lines).strip()


def replies_status(reply_body: str) -> str:
    if not reply_body.strip():
        return "Unknown"
    failure_patterns = [
        r'(?i)"success_ind"\s*:\s*"?0"?',
        r'(?i)"successindicator"\s*:\s*"?0"?',
        r'(?i)"successIndicator"\s*:\s*"?0"?',
        r'(?i)"status"\s*:\s*"(F|0)"',
        r'(?i)"operationstatus"\s*:\s*"F"',
        r'(?i)"status_data"\s*:\s*\{[\s\S]*?"status"\s*:\s*"F"',
    ]
    for p in failure_patterns:
        if re.search(p, reply_body):
            return "Failure in replies.yaml"
    success_patterns = [
        r'(?i)"success_ind"\s*:\s*"?1"?',
        r'(?i)"successindicator"\s*:\s*"?1"?',
        r'(?i)"successIndicator"\s*:\s*"?1"?',
        r'(?i)"status"\s*:\s*"(S|Z|1)"',
        r'(?i)"operationstatus"\s*:\s*"S"',
    ]
    for p in success_patterns:
        if re.search(p, reply_body):
            return "Success in replies.yaml"
    return "Unknown in replies.yaml"


def parse_replies(replies_paths: List[str]) -> Dict[str, Dict[str, str]]:
    result: Dict[str, Dict[str, str]] = {}
    pat = re.compile(r'(?ms)^\s*-\s*transName:\s*"([^"]+)"\s*\r?\n\s*replyBody:\s*\|-\s*\r?\n(.*?)(?=^\s*-\s*transName:\s*"|\Z)')
    for fp in replies_paths:
        try:
            raw = Path(fp).read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for m in pat.finditer(raw):
            tx = m.group(1).strip()
            if not tx or tx in result:
                continue
            body_raw = remove_common_indent(m.group(2))
            body_pretty = try_pretty_json(body_raw) or body_raw
            result[tx] = {
                "Status": replies_status(body_raw),
                "Body": body_pretty,
                "FileName": Path(fp).name,
                "SourcePath": fp,
            }
    return result


def format_range_block(lines: List[str], start: int, end: int, max_lines: int) -> Dict[str, Any]:
    s = max(0, start)
    e = min(len(lines) - 1, end)
    trunc = False
    if (e - s + 1) > max_lines:
        e = s + max_lines - 1
        trunc = True
    out = [f"{i+1:06d}: {lines[i]}" for i in range(s, e + 1)]
    text = "\n".join(out)
    if trunc:
        text += "\n...(truncated; expand range in raw log for full section)"
    return {"StartLine": s + 1, "EndLine": e + 1, "Text": text}


def resolve_json_path_value(json_text: str, path_expr: str) -> Optional[str]:
    try:
        obj = json.loads(json_text)
    except Exception:
        return None
    cur: Any = obj
    for seg in path_expr.split("."):
        for m in re.finditer(r"([^\[\]]+)|\[(\d+)\]", seg):
            if m.group(1):
                key = m.group(1)
                if isinstance(cur, dict) and key in cur:
                    cur = cur[key]
                else:
                    return None
            else:
                idx = int(m.group(2))
                if isinstance(cur, list) and 0 <= idx < len(cur):
                    cur = cur[idx]
                else:
                    return None
    if cur is None:
        return "null"
    if isinstance(cur, (str, int, float, bool)):
        return str(cur)
    return json.dumps(cur, ensure_ascii=False, separators=(",", ":"))


def get_transaction_hit_indexes(lines: List[str], tx: str) -> List[int]:
    hits: List[int] = []
    if not tx:
        return hits
    probe = tx.strip()
    truncated = probe.endswith("...")
    if truncated:
        probe = probe[:-3]
    probe_lower = probe.lower()
    for i, line in enumerate(lines):
        line_lower = line.lower()
        is_match = False
        if not truncated:
            is_match = probe_lower in line_lower
        else:
            for m in re.finditer(r"(?i)\[([^\]]+)\]", line):
                if m.group(1).lower().startswith(probe_lower):
                    is_match = True
                    break
            if not is_match:
                is_match = probe_lower in line_lower
        if is_match:
            hits.append(i)
    return hits


def get_transaction_window(lines: List[str], tx: str, hint_indexes: List[int]) -> Optional[Dict[str, int]]:
    if not lines or not tx:
        return None
    probe = tx.strip()
    truncated = probe.endswith("...")
    if truncated:
        probe = probe[:-3]
    esc = re.escape(probe)
    strong: List[int] = []
    weak: List[int] = []

    for i, line in enumerate(lines):
        if (not truncated) and re.search(rf"(?i)\[\d+\]\s+\[{esc}\]\s+replacing\s+\$\{{", line):
            strong.append(i)
        elif truncated:
            m = re.search(r"(?i)\[\d+\]\s+\[([^\]]+)\]\s+replacing\s+\$\{", line)
            if m and m.group(1).lower().startswith(probe.lower()):
                strong.append(i)
        if (not truncated) and re.search(rf"(?i)\[{esc}\]", line):
            weak.append(i)
        elif truncated and (probe.lower() in line.lower()):
            weak.append(i)

    start: Optional[int] = None
    if strong:
        start = min(strong)
    elif weak:
        start = min(weak)
    elif hint_indexes:
        start = min(hint_indexes)
    else:
        return None

    start_user: Optional[str] = None
    m = re.search(r"(?i)\[(\d+)\]\s+\[", lines[start])
    if m:
        start_user = m.group(1)

    next_tx_start: Optional[int] = None
    for j in range(start + 1, len(lines)):
        m2 = re.search(r"(?i)\[(\d+)\]\s+\[([^\]]+)\]\s+replacing\s+\$\{", lines[j])
        if not m2:
            continue
        cand_user = m2.group(1)
        cand_tx = m2.group(2)
        if start_user is not None and cand_user != start_user:
            continue
        same_tx = cand_tx.lower().startswith(probe.lower()) if truncated else (cand_tx.lower() == tx.lower())
        if not same_tx:
            next_tx_start = j
            break

    hard_cap_end = min(len(lines) - 1, start + 7000)
    end = min(hard_cap_end, next_tx_start - 1) if next_tx_start is not None else hard_cap_end
    if (end - start) < 120:
        end = min(len(lines) - 1, start + 1200)
    return {"Start": start, "End": end}


def build_global_json_indexes(lines: List[str]) -> Dict[str, Any]:
    request_candidates: List[Dict[str, Any]] = []
    response_candidates: List[Dict[str, Any]] = []
    requests_by_tx: Dict[str, List[Dict[str, Any]]] = {}
    responses_by_reqname: Dict[str, List[Dict[str, Any]]] = {}

    recent_replacements: List[Tuple[int, str]] = []
    replacement_re = re.compile(r"(?i)\[(\d+)\]\s+\[([^\]]+)\]\s+replacing\s+\$\{")
    response_patterns = [
        re.compile(r"(?i)Request failed, reply body:\s*(.+)$"),
        re.compile(r"(?i)Dumping body of reply for\s+.+?:\s*(.+)$"),
        re.compile(r"(?i)\breply body\b\s*[:=-]\s*(.+)$"),
        re.compile(r"(?i)SimulationProcessor\s*-\s*Body:\s*(\{.+)$"),
    ]

    def nearest_tx(before_idx: int) -> Optional[str]:
        for li, tx in reversed(recent_replacements):
            if li <= before_idx:
                return tx
        return None

    for i, line in enumerate(lines):
        m_rep = replacement_re.search(line)
        if m_rep:
            recent_replacements.append((i, m_rep.group(2)))
            if len(recent_replacements) > 20000:
                recent_replacements = recent_replacements[-10000:]

        if re.search(r"(?i)final body:\s*\{", line):
            pretty = try_pretty_json_from_lines(lines, i)
            if pretty:
                req_name = parse_request_name(pretty)
                tx = nearest_tx(i)
                req_obj = {
                    "Line": i + 1,
                    "Json": pretty,
                    "RequestName": req_name or "",
                    "Transaction": tx or "",
                }
                request_candidates.append(req_obj)
                if tx:
                    requests_by_tx.setdefault(tx, []).append(req_obj)

        payload = None
        for p in response_patterns:
            m = p.search(line)
            if m:
                payload = m.group(1)
                break
        if payload:
            pretty = try_pretty_json(payload) or try_pretty_json_from_lines(lines, i)
            if pretty:
                req_name = parse_request_name(pretty)
                resp_obj = {
                    "Line": i + 1,
                    "Json": pretty,
                    "RequestName": req_name or "",
                }
                response_candidates.append(resp_obj)
                if req_name:
                    responses_by_reqname.setdefault(req_name.lower(), []).append(resp_obj)

    for k in requests_by_tx.keys():
        requests_by_tx[k].sort(key=lambda x: x["Line"])
    for k in responses_by_reqname.keys():
        responses_by_reqname[k].sort(key=lambda x: x["Line"])

    return {
        "requestCandidates": request_candidates,
        "responseCandidates": response_candidates,
        "requestsByTransaction": requests_by_tx,
        "responsesByRequestName": responses_by_reqname,
    }


def find_request_json_in_window(lines: List[str], start: int, end: int) -> Optional[Dict[str, Any]]:
    if not lines or start < 0 or end < start:
        return None
    request_search_end = min(len(lines) - 1, end + 80)
    for j in range(start, request_search_end + 1):
        if re.search(r"(?i)final body:\s*\{", lines[j]):
            pretty = try_pretty_json_from_lines(lines, j)
            if pretty:
                return {"Line": j + 1, "Json": pretty}
    return None


def find_response_json_in_window(lines: List[str], start: int, end: int, expected_request_name: Optional[str]) -> Optional[Dict[str, Any]]:
    if not lines or start < 0 or end < start:
        return None
    req_esc = re.escape(expected_request_name) if expected_request_name else None
    response_search_end = min(len(lines) - 1, end + 2800)
    patterns = [
        r"(?i)Request failed, reply body:\s*(.+)$",
        r"(?i)Dumping body of reply for\s+.+?:\s*(.+)$",
        r"(?i)\breply body\b\s*[:=-]\s*(.+)$",
        r"(?i)SimulationProcessor\s*-\s*Body:\s*(\{.+)$",
    ]
    for j in range(start, response_search_end + 1):
        payload = None
        for p in patterns:
            m = re.search(p, lines[j])
            if m:
                payload = m.group(1)
                break
        if not payload:
            continue
        pretty = try_pretty_json(payload) or try_pretty_json_from_lines(lines, j)
        if not pretty:
            continue
        if req_esc and not re.search(rf'(?i)"requestName"\s*:\s*"{req_esc}"', pretty):
            continue
        return {"Line": j + 1, "Json": pretty}

    if req_esc:
        wide_end = min(len(lines) - 1, start + 12000)
        for j in range(start, wide_end + 1):
            m = re.search(r"(?i)SimulationProcessor\s*-\s*Body:\s*(\{.+)$", lines[j]) or re.search(
                r"(?i)Dumping body of reply for\s+.+?:\s*(.+)$", lines[j]
            )
            if not m:
                continue
            payload = m.group(1)
            pretty = try_pretty_json(payload) or try_pretty_json_from_lines(lines, j)
            if not pretty:
                continue
            if not re.search(rf'(?i)"requestName"\s*:\s*"{req_esc}"', pretty):
                continue
            return {"Line": j + 1, "Json": pretty}
    return None


def resolve_replies_entry_for_transaction(replies_map: Dict[str, Dict[str, str]], tx: str) -> Optional[Dict[str, str]]:
    if tx in replies_map:
        return replies_map[tx]
    probe = tx.strip()
    if probe.endswith("..."):
        prefix = probe[:-3].lower()
        for k, v in replies_map.items():
            if k.lower().startswith(prefix):
                return v
    return None


def get_missing_token_dependency(outcomes: str, lines: List[str], window_start: int, window_end: int) -> Optional[Dict[str, Any]]:
    if not FAIL_BUILD_RE.search(outcomes):
        return None
    search_start = window_start if window_start >= 0 else 0
    search_end = min(len(lines) - 1, window_end + 80) if window_end >= search_start else len(lines) - 1
    for i in range(search_start, search_end + 1):
        line = lines[i]
        if FAIL_BUILD_RE.search(line) and FAIL_BUILD_STORED_RE.search(line):
            m = TOKEN_RE.search(line)
            if not m:
                continue
            expr = m.group(1).strip()
            src = expr.split(".", 1)[0] if expr else ""
            if not src:
                return None
            return {"TokenExpression": expr, "SourceTransaction": src, "ErrorLine": i + 1}
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-path", required=True)
    ap.add_argument("--scenario-dir", required=True)
    ap.add_argument("--output-json", required=True)
    ap.add_argument("--cache-path", required=False)
    args = ap.parse_args()

    out_path = Path(args.out_path)
    if not out_path.exists():
        raise SystemExit(f".out not found: {out_path}")
    cache_path = Path(args.cache_path) if args.cache_path else Path(str(out_path) + ".report-index.json")
    st = out_path.stat()
    cache_key = {"path": str(out_path.resolve()), "size": st.st_size, "mtime": st.st_mtime_ns}

    if cache_path.exists():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            if cached.get("cacheKey") == cache_key and "data" in cached:
                Path(args.output_json).write_text(json.dumps(cached["data"], ensure_ascii=False), encoding="utf-8")
                eprint(f"report_parser_fast.py: cache hit -> {cache_path}")
                return 0
        except Exception:
            pass

    lines = out_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    report_lines = [strip_ansi(x) for x in lines]
    summary_rows, all_tx_from_requests = parse_requests_and_errors(report_lines)
    global_index = build_global_json_indexes(lines)
    ordered_txs: List[str] = []
    seen = set()
    for r in summary_rows:
        tx = r["Transaction"]
        if tx not in seen:
            seen.add(tx)
            ordered_txs.append(tx)

    replies_paths = resolve_replies_paths(args.scenario_dir)
    replies_map = parse_replies(replies_paths)
    txs_with_summary_rows = {str(r.get("Transaction", "")) for r in summary_rows}
    for tx_name, rep in replies_map.items():
        st = str(rep.get("Status", "")).strip()
        if tx_name in txs_with_summary_rows:
            continue
        if st not in ("Failure in replies.yaml", "Unknown in replies.yaml"):
            continue
        summary_rows.append({"Transaction": tx_name, "Outcome": "replies.yaml status only", "Source": "REPLIES"})
        txs_with_summary_rows.add(tx_name)
        if tx_name not in seen:
            seen.add(tx_name)
            ordered_txs.append(tx_name)

    details: Dict[str, Dict[str, Any]] = {}
    outcomes_by_tx: Dict[str, List[str]] = {}
    for r in summary_rows:
        outcomes_by_tx.setdefault(r["Transaction"], []).append(r["Outcome"])
    used_request_lines = set()
    used_response_lines = set()

    for tx in ordered_txs:
        hits = get_transaction_hit_indexes(lines, tx)
        window = get_transaction_window(lines, tx, hits)
        start = window["Start"] if window else None
        end = window["End"] if window else None

        matched = []
        seen_lines = set()
        for h in hits:
            s0 = f"{h+1:06d}: {truncate_text(lines[h].strip(), 2000)}"
            if s0 not in seen_lines:
                seen_lines.add(s0)
                matched.append(s0)
            for j in range(max(0, h - 2), min(len(lines) - 1, h + 2) + 1):
                s = f"{j+1:06d}: {truncate_text(lines[j].strip(), 2000)}"
                if s not in seen_lines:
                    seen_lines.add(s)
                    matched.append(s)

        req_line = None
        req_json = None
        resp_line = None
        resp_json = None
        failure_focus = None
        if start is not None and end is not None:
            req_obj = find_request_json_in_window(lines, start, end)
            if req_obj:
                req_line = req_obj["Line"]
                req_json = req_obj["Json"]
            expected_req = None
            if req_json:
                mm = REQ_JSON_RE.search(req_json)
                expected_req = mm.group(1) if mm else None
            resp_obj = find_response_json_in_window(lines, start, end, expected_req)
            if resp_obj:
                resp_line = resp_obj["Line"]
                resp_json = resp_obj["Json"]
            if failure_focus is None:
                for j in range(start, min(len(lines) - 1, end + 350) + 1):
                    if KW_FAILURE_RE.search(lines[j]):
                        failure_focus = j
                        break

        if req_line and req_line in used_request_lines:
            req_line = None
            req_json = None
        if not req_json:
            for cand in global_index["requestsByTransaction"].get(tx, []):
                line_no = int(cand["Line"])
                if line_no in used_request_lines:
                    continue
                req_line = line_no
                req_json = str(cand["Json"])
                break
        if req_line:
            used_request_lines.add(int(req_line))

        expected_req = parse_request_name(req_json)
        if resp_line and resp_line in used_response_lines:
            resp_line = None
            resp_json = None
        if not resp_json and expected_req:
            req_line_floor = int(req_line) if req_line else 0
            for cand in global_index["responsesByRequestName"].get(expected_req.lower(), []):
                line_no = int(cand["Line"])
                if line_no in used_response_lines:
                    continue
                if line_no < req_line_floor:
                    continue
                resp_line = line_no
                resp_json = str(cand["Json"])
                break
        if not resp_json:
            req_line_floor = int(req_line) if req_line else 0
            for cand in global_index["responseCandidates"]:
                line_no = int(cand["Line"])
                if line_no in used_response_lines:
                    continue
                if line_no < req_line_floor:
                    continue
                resp_line = line_no
                resp_json = str(cand["Json"])
                break
        if resp_line:
            used_response_lines.add(int(resp_line))

        range_blocks = []
        if start is not None and end is not None:
            wb = format_range_block(lines, start, end, 1500)
            wb["Title"] = "Transaction Window"
            range_blocks.append(wb)
        if failure_focus is not None and not (start is not None and end is not None and failure_focus >= start and failure_focus <= end):
            fb = format_range_block(lines, max(0, failure_focus - 40), min(len(lines) - 1, failure_focus + 220), 1200)
            fb["Title"] = "Failure Trace"
            range_blocks.append(fb)

        replies = resolve_replies_entry_for_transaction(replies_map, tx)
        detail = {
            "MatchedLines": matched,
            "RangeBlocks": range_blocks,
            "RequestJson": [req_json] if req_json else [],
            "ResponseJson": [resp_json] if resp_json else [],
            "RequestLine": req_line,
            "ResponseLine": resp_line,
            "WindowStartLine": (start + 1) if start is not None else None,
            "WindowEndLine": (end + 1) if end is not None else None,
            "Recommendation": "",
            "RepliesYamlState": replies["Status"] if replies else "Not found in replies*.yaml",
            "RepliesYamlFileName": replies["FileName"] if replies else "",
            "RepliesYamlBody": replies["Body"] if replies else "",
            "MissingTokenExpression": "",
            "MissingTokenErrorLine": None,
            "DependencySourceTransaction": "",
            "DependencyRequestJson": "",
            "DependencyRequestLine": None,
            "DependencyResponseJson": "",
            "DependencyResponseLine": None,
            "DependencyRepliesYamlState": "Not found in replies*.yaml",
            "DependencyRepliesYamlFileName": "",
            "DependencyRepliesYamlBody": "",
            "DependencyTokenPathInReplies": "",
            "DependencyTokenValueFromReplies": "",
        }

        outcomes = " | ".join(outcomes_by_tx.get(tx, []))
        dep_info = get_missing_token_dependency(
            outcomes=outcomes,
            lines=lines,
            window_start=(start if start is not None else -1),
            window_end=(end if end is not None else -1),
        )
        if dep_info:
            expr = dep_info["TokenExpression"]
            src = dep_info["SourceTransaction"]
            detail["MissingTokenExpression"] = expr
            detail["MissingTokenErrorLine"] = dep_info["ErrorLine"]
            detail["DependencySourceTransaction"] = src

            dep_hits = get_transaction_hit_indexes(lines, src)
            dep_window = get_transaction_window(lines, src, dep_hits)
            if dep_window:
                dep_req_obj = find_request_json_in_window(lines, dep_window["Start"], dep_window["End"])
                if dep_req_obj:
                    detail["DependencyRequestJson"] = dep_req_obj["Json"]
                    detail["DependencyRequestLine"] = dep_req_obj["Line"]
                dep_expected = None
                if detail["DependencyRequestJson"]:
                    mm_dep = REQ_JSON_RE.search(detail["DependencyRequestJson"])
                    dep_expected = mm_dep.group(1) if mm_dep else None
                dep_resp_obj = find_response_json_in_window(lines, dep_window["Start"], dep_window["End"], dep_expected)
                if dep_resp_obj:
                    detail["DependencyResponseJson"] = dep_resp_obj["Json"]
                    detail["DependencyResponseLine"] = dep_resp_obj["Line"]

            dep_rep = resolve_replies_entry_for_transaction(replies_map, src)
            if dep_rep:
                detail["DependencyRepliesYamlState"] = dep_rep["Status"]
                detail["DependencyRepliesYamlFileName"] = dep_rep["FileName"]
                detail["DependencyRepliesYamlBody"] = dep_rep["Body"]
            path = expr[len(src) + 1 :] if expr.lower().startswith(src.lower() + ".") else expr
            detail["DependencyTokenPathInReplies"] = path
            if dep_rep and path:
                val = resolve_json_path_value(dep_rep["Body"], path)
                if val is not None:
                    detail["DependencyTokenValueFromReplies"] = val
        if FAIL_BUILD_RE.search(outcomes):
            tok = detail["MissingTokenExpression"]
            detail["Recommendation"] = (
                f"Fix missing dependency value ${{{tok}}} before this step (seed prior transaction output or add guard/default handling)."
                if tok
                else "Request template failed before send; verify placeholder variables come from earlier responses and add null/exists checks in YAML extraction."
            )
        elif "KO=" in outcomes:
            if detail["RepliesYamlState"] == "Failure in replies.yaml":
                detail["Recommendation"] = "Service returned failure status. Compare request/response in this section and validate required fields, domain data, and operation-specific permissions."
            else:
                detail["Recommendation"] = "KO detected without explicit build error. Review transaction window and failure trace to confirm request payload values and downstream dependency order."
        else:
            detail["Recommendation"] = "Review request/response and failure trace for this transaction; start with requestName/status_data and validate prerequisite transaction outputs."

        details[tx] = detail

    anchor_counter: Dict[str, int] = {}
    anchor_map: Dict[str, str] = {}
    for tx in ordered_txs:
        base = re.sub(r"[^a-z0-9]+", "-", tx.lower()).strip("-") or "tx"
        anchor_counter[base] = anchor_counter.get(base, 0) + 1
        anchor_map[tx] = base if anchor_counter[base] == 1 else f"{base}-{anchor_counter[base]}"

    data = {
        "summaryRows": summary_rows,
        "allTransactionNames": all_tx_from_requests,
        "orderedTransactions": ordered_txs,
        "anchorByTransaction": anchor_map,
        "detailsByTransaction": details,
        "repliesYamlPathDisplay": "; ".join(replies_paths) if replies_paths else "Not found",
    }

    Path(args.output_json).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    cache_path.write_text(json.dumps({"cacheKey": cache_key, "data": data}, ensure_ascii=False), encoding="utf-8")
    eprint(f"report_parser_fast.py: parsed and cached -> {cache_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
