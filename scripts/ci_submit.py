#!/usr/bin/env python3
"""CI helper: pick the target App Store version, wait for a build, attach it, and
submit for review — used by the GitHub Actions release pipeline.

Self-contained: only needs `cryptography` (for the ES256 JWT). Auth comes from the
App Store Connect API key.

Env:
  ASC_KEY_ID, ASC_ISSUER_ID            ASC API key id + issuer
  ASC_API_PRIVATE_KEY                  the .p8 contents (or ASC_PRIVATE_KEY_PATH)
  ASC_BUNDLE_ID                        e.g. com.tertiaryinfotech.freefood

Subcommands:
  next-version                         print the version string CI should build/submit
  wait-build --build <n>               block until that build is processed (VALID)
  submit --version <v> --build <n> [--screenshots-dir DIR]
                                       ensure version v exists (create+copy metadata/
                                       screenshots if new), attach build n, submit for review
"""
import argparse, base64, hashlib, json, os, re, sys, time, urllib.error, urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

BASE = "https://api.appstoreconnect.apple.com"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def token():
    pem = os.environ.get("ASC_API_PRIVATE_KEY")
    if pem:
        key = serialization.load_pem_private_key(pem.encode(), None)
    else:
        with open(os.path.expanduser(os.environ["ASC_PRIVATE_KEY_PATH"]), "rb") as f:
            key = serialization.load_pem_private_key(f.read(), None)
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + b"." +
                     b64url(json.dumps(payload, separators=(",", ":")).encode()))
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return (signing_input + b"." + b64url(sig)).decode()


def call(method, path, body=None, tok=None, raw=None, headers=None):
    h = {"Authorization": f"Bearer {tok}"}
    data = None
    if raw is not None:
        data = raw
    elif body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    if headers:
        h.update(headers)
    req = urllib.request.Request(path if path.startswith("http") else BASE + path,
                                 data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, (r.read().decode() or "")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def jget(method, path, tok, body=None):
    s, b = call(method, path, body=body, tok=tok)
    return s, (json.loads(b) if b.strip().startswith(("{", "[")) else b)


def app_id(tok):
    bid = os.environ["ASC_BUNDLE_ID"]
    s, d = jget("GET", f"/v1/apps?filter[bundleId]={bid}&limit=1", tok)
    if not d.get("data"):
        sys.exit(f"No app for bundle id {bid}")
    return d["data"][0]["id"]


def versions(tok, aid):
    s, d = jget("GET", f"/v1/apps/{aid}/appStoreVersions?limit=20", tok)
    return d.get("data", [])


def vkey(s):
    parts = (s.split(".") + ["0", "0"])[:3]
    return tuple(int(p) for p in parts)


def bump(s):
    parts = s.split(".")
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)


def project_marketing_version():
    """The developer-controlled marketing version — the source of truth for what to ship.
    Read from project.yml (XcodeGen)."""
    try:
        for line in open("project.yml"):
            m = re.search(r'MARKETING_VERSION:\s*"?([0-9]+(?:\.[0-9]+)*)"?', line)
            if m:
                return m.group(1)
    except OSError:
        pass
    return None


def cmd_next_version(_):
    # Prefer the version the developer set in the project — CI ships exactly that, and
    # ensure_version() reconciles App Store Connect to it (create, or rename a pending one).
    pv = project_marketing_version()
    if pv:
        print(pv); return
    tok = token(); aid = app_id(tok)
    vs = versions(tok, aid)
    if not vs:
        print("1.0"); return
    latest = max(vs, key=lambda v: vkey(v["attributes"]["versionString"]))
    state = latest["attributes"]["appStoreState"]
    vstr = latest["attributes"]["versionString"]
    print(vstr if state in EDITABLE else bump(vstr))


def cmd_wait_build(a):
    tok = token(); aid = app_id(tok)
    for _ in range(90):  # ~30 min — App Store processing is sometimes slow to index a build
        s, d = jget("GET", f"/v1/builds?filter[app]={aid}&sort=-uploadedDate&limit=10", tok)
        match = [b for b in d.get("data", []) if str(b["attributes"]["version"]) == str(a.build)]
        if match:
            st = match[0]["attributes"]["processingState"]
            print(f"build {a.build}: {st}", flush=True)
            if st == "VALID":
                return
            if st in ("INVALID", "FAILED"):
                sys.exit(f"build {a.build} processing {st}")
        else:
            print(f"build {a.build}: not indexed yet", flush=True)
        time.sleep(20)
    sys.exit("timed out waiting for build to process")


def localization(tok, vid):
    s, d = jget("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", tok)
    return d.get("data", [])


def changelog_notes(version, path="CHANGELOG.md"):
    """Release notes for `version` from CHANGELOG.md (falls back to the [Unreleased] section),
    as a plain-text bullet list for the App Store 'What's New' field."""
    try:
        text = open(path).read()
    except OSError:
        return None
    chosen, unreleased = None, None
    for block in re.split(r"(?m)^##\s+", text)[1:]:
        head = block.splitlines()[0]
        if f"[{version}]" in head:
            chosen = block
        elif "Unreleased" in head:
            unreleased = block
    block = chosen or unreleased
    if not block:
        return None
    bullets = []
    for line in block.splitlines():
        s = line.strip()
        if s.startswith("- "):
            bullets.append("• " + re.sub(r"[*`]", "", s[2:]).strip())
    if not bullets:
        return None
    return "\n".join(bullets)[:3990]


def cancel_active(tok, aid):
    """Cancel any in-review submission so the version becomes editable again."""
    s, d = jget("GET", f"/v1/reviewSubmissions?filter[app]={aid}&limit=20", tok)
    for x in d.get("data", []):
        if x["attributes"]["state"] in ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"):
            call("PATCH", f"/v1/reviewSubmissions/{x['id']}",
                 {"data": {"type": "reviewSubmissions", "id": x["id"], "attributes": {"canceled": True}}}, tok)
            print(f"cancelled active review {x['id']}", flush=True)


def set_whats_new(tok, vid, notes):
    """Record the changelog as the version's 'What's New' (ignored on a first release).
    The version must be editable, so retry while a just-cancelled review is still locking it."""
    if not notes:
        return
    locs = localization(tok, vid)
    if not locs:
        return
    lid = locs[0]["id"]
    for _ in range(8):
        s, b = call("PATCH", f"/v1/appStoreVersionLocalizations/{lid}",
                    {"data": {"type": "appStoreVersionLocalizations", "id": lid,
                              "attributes": {"whatsNew": notes}}}, tok)
        if s < 300:
            print("whatsNew set from CHANGELOG", flush=True)
            return
        if s == 409:  # version still locked by the cancelling review — wait and retry
            time.sleep(5)
            continue
        break
    print(f"whatsNew not set ({s}) — likely first release", flush=True)


def copy_metadata(tok, src_vid, dst_vid):
    src = localization(tok, src_vid)
    if not src:
        return
    a = src[0]["attributes"]
    body = {"data": {"type": "appStoreVersionLocalizations",
            "attributes": {k: a.get(k) for k in
                           ("locale", "description", "keywords", "promotionalText",
                            "supportUrl", "marketingUrl", "whatsNew") if a.get(k)},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": dst_vid}}}}}
    # a fresh version already has an en-US localization; patch it instead of creating a dup
    dst = localization(tok, dst_vid)
    if dst:
        lid = dst[0]["id"]
        call("PATCH", f"/v1/appStoreVersionLocalizations/{lid}",
             {"data": {"type": "appStoreVersionLocalizations", "id": lid,
                       "attributes": {k: v for k, v in body["data"]["attributes"].items() if k != "locale"}}}, tok)
    else:
        call("POST", "/v1/appStoreVersionLocalizations", body, tok)


def upload_screenshots(tok, vid, directory):
    locs = localization(tok, vid)
    if not locs:
        return
    lid = locs[0]["id"]
    s, sets = jget("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets", tok)
    set_id = None
    for st in sets.get("data", []):
        if st["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67":
            set_id = st["id"]
    if not set_id:
        s, b = call("POST", "/v1/appScreenshotSets",
                    {"data": {"type": "appScreenshotSets",
                              "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                              "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": lid}}}}}, tok)
        set_id = json.loads(b)["data"]["id"]
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        data = open(path, "rb").read()
        s, b = call("POST", "/v1/appScreenshots",
                    {"data": {"type": "appScreenshots",
                              "attributes": {"fileName": name, "fileSize": len(data)},
                              "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}}, tok)
        d = json.loads(b)["data"]
        for op in d["attributes"]["uploadOperations"]:
            hdr = {h["name"]: h["value"] for h in op["requestHeaders"]}
            call(op["method"], op["url"], raw=data[op["offset"]:op["offset"] + op["length"]], tok=tok, headers=hdr)
        call("PATCH", f"/v1/appScreenshots/{d['id']}",
             {"data": {"type": "appScreenshots", "id": d["id"],
                       "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}, tok)
        print(f"  uploaded screenshot {name}", flush=True)


def ensure_version(tok, aid, target, screenshots_dir):
    vs = versions(tok, aid)
    for v in vs:
        if v["attributes"]["versionString"] == target:
            return v["id"], False
    # create the next version and carry metadata + screenshots from the most recent one
    prev = max(vs, key=lambda v: vkey(v["attributes"]["versionString"])) if vs else None
    s, b = call("POST", "/v1/appStoreVersions",
                {"data": {"type": "appStoreVersions",
                          "attributes": {"platform": "IOS", "versionString": target, "releaseType": "AFTER_APPROVAL"},
                          "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}, tok)
    if s >= 300:
        # An app can't hold two un-released versions. If one already exists and is editable
        # (or sitting in review), repurpose it as `target` rather than creating a duplicate —
        # this is the "existing app in App Store Connect -> update to a new version" path.
        cand = next((v for v in vs if v["attributes"]["appStoreState"] in EDITABLE), None)
        if cand:
            cancel_active(tok, aid)            # release any in-review hold so the string is editable
            cid, cur = cand["id"], cand["attributes"]["versionString"]
            for _ in range(8):
                rs, rb = call("PATCH", f"/v1/appStoreVersions/{cid}",
                              {"data": {"type": "appStoreVersions", "id": cid,
                                        "attributes": {"versionString": target}}}, tok)
                if rs < 300:
                    print(f"repurposed existing version {cur} -> {target}", flush=True)
                    return cid, False
                if rs == 409:                  # cancel is async and still holds the version
                    time.sleep(5); continue
                break
            sys.exit(f"could not update existing version to {target}: {rb[:300]}")
        sys.exit(f"create version {target} failed: {b[:300]}")
    vid = json.loads(b)["data"]["id"]
    print(f"created App Store version {target}", flush=True)
    if prev:
        copy_metadata(tok, prev["id"], vid)
    if screenshots_dir and os.path.isdir(screenshots_dir):
        upload_screenshots(tok, vid, screenshots_dir)
    return vid, True


def attach_build(tok, aid, vid, build_number):
    s, d = jget("GET", f"/v1/apps/{aid}/builds?limit=50", tok)
    target = next((b for b in d["data"] if str(b["attributes"]["version"]) == str(build_number)), None)
    if not target:
        sys.exit(f"build {build_number} not found")
    s, _ = call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                {"data": {"type": "builds", "id": target["id"]}}, tok)
    print(f"attached build {build_number}: {s}", flush=True)


def submit_for_review(tok, aid, vid):
    # Cancel anything actively in review; remember an empty draft to reuse.
    s, d = jget("GET", f"/v1/reviewSubmissions?filter[app]={aid}&limit=20", tok)
    draft = None
    for x in d.get("data", []):
        st = x["attributes"]["state"]
        if st in ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"):
            call("PATCH", f"/v1/reviewSubmissions/{x['id']}",
                 {"data": {"type": "reviewSubmissions", "id": x["id"], "attributes": {"canceled": True}}}, tok)
            print(f"cancelled active review {x['id']}", flush=True)
        elif st == "READY_FOR_REVIEW":
            draft = x["id"]  # reuse a leftover draft instead of creating another

    # Cancelling is async and keeps "holding" the version, so retry create/add/submit.
    last = ""
    for attempt in range(15):
        if not draft:
            s, b = call("POST", "/v1/reviewSubmissions",
                        {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                                  "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}, tok)
            if s >= 300:
                last = b; time.sleep(6); continue
            draft = json.loads(b)["data"]["id"]
        s, items = jget("GET", f"/v1/reviewSubmissions/{draft}/items", tok)
        if not items.get("data"):
            s, b = call("POST", "/v1/reviewSubmissionItems",
                        {"data": {"type": "reviewSubmissionItems",
                                  "relationships": {
                                      "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": draft}},
                                      "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}, tok)
            if s >= 300:  # version still held by the cancelling submission — wait and retry
                last = b; time.sleep(6); continue
        s, b = call("PATCH", f"/v1/reviewSubmissions/{draft}",
                    {"data": {"type": "reviewSubmissions", "id": draft, "attributes": {"submitted": True}}}, tok)
        if s < 300:
            print("SUBMITTED for review", flush=True)
            return
        last = b
        time.sleep(6)
    sys.exit(f"submit failed after retries: {last[:400]}")


def cmd_submit(a):
    tok = token(); aid = app_id(tok)
    vid, created = ensure_version(tok, aid, a.version, a.screenshots_dir)
    cancel_active(tok, aid)                                    # free the version for edits
    set_whats_new(tok, vid, changelog_notes(a.version))       # record CHANGELOG as What's New
    attach_build(tok, aid, vid, a.build)
    submit_for_review(tok, aid, vid)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("next-version").set_defaults(func=cmd_next_version)
    w = sub.add_parser("wait-build"); w.add_argument("--build", required=True); w.set_defaults(func=cmd_wait_build)
    s = sub.add_parser("submit")
    s.add_argument("--version", required=True)
    s.add_argument("--build", required=True)
    s.add_argument("--screenshots-dir", default="ci/screenshots/APP_IPHONE_67")
    s.set_defaults(func=cmd_submit)
    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
