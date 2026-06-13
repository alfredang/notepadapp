#!/usr/bin/env python3
"""App Store Connect submission helper (API-first).

Loads .env, mints a JWT via asc_jwt.swift (sibling file), and drives the common
submission tasks. Reusable across projects — set the per-project values via env
or flags.

Env (load `.env` first: `set -a; source .env; set +a`):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH   (credentials; .p8 stays outside repo)
  ASC_BUNDLE_ID            reverse-DNS bundle id, e.g. com.yourorg.app  (to locate the app)
  ASC_APP_ID               numeric ASC app id (optional; resolved from bundle id if absent)
  ASC_PRIVACY_POLICY_URL, ASC_SUPPORT_URL, ASC_MARKETING_URL, ASC_COPYRIGHT
  ASC_CONTACT_FIRST, ASC_CONTACT_LAST, ASC_CONTACT_PHONE, ASC_CONTACT_EMAIL
  ASC_REVIEW_NOTES

Usage:
  python3 asc_submit.py status
  python3 asc_submit.py set-metadata
  python3 asc_submit.py review-contact
  python3 asc_submit.py attach-build --build 2
  python3 asc_submit.py screenshots --type APP_IPAD_PRO_3GEN_129 a.png b.png
  python3 asc_submit.py submit
"""
import argparse, hashlib, json, os, subprocess, sys, urllib.error, urllib.request

BASE = "https://api.appstoreconnect.apple.com"
HERE = os.path.dirname(os.path.abspath(__file__))


def token():
    out = subprocess.run(["swift", os.path.join(HERE, "asc_jwt.swift")],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("JWT error: " + out.stderr.strip())
    return out.stdout.strip()


def call(method, path, body=None, tok=None):
    tok = tok or token()
    req = urllib.request.Request(
        BASE + path,
        data=(json.dumps(body).encode() if body else None),
        method=method,
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        r = urllib.request.urlopen(req)
        return r.status, (r.read().decode() or "")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def jget(method, path, tok=None):
    s, b = call(method, path, tok=tok)
    return s, (json.loads(b) if b.strip().startswith(("{", "[")) else b)


def app_id(tok):
    if os.environ.get("ASC_APP_ID"):
        return os.environ["ASC_APP_ID"]
    bid = os.environ["ASC_BUNDLE_ID"]
    s, d = jget("GET", f"/v1/apps?filter[bundleId]={bid}&limit=1", tok)
    if not d.get("data"):
        sys.exit(f"No app for bundle id {bid}")
    return d["data"][0]["id"]


def latest_version(tok, aid):
    s, d = jget("GET", f"/v1/apps/{aid}/appStoreVersions?limit=10", tok)
    # prefer an editable version
    for v in d["data"]:
        if v["attributes"]["appStoreState"] in (
                "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                "METADATA_REJECTED", "WAITING_FOR_REVIEW"):
            return v
    return d["data"][0] if d.get("data") else None


def cmd_status(a):
    tok = token(); aid = app_id(tok)
    s, app = jget("GET", f"/v1/apps/{aid}", tok)
    print("app:", aid, app["data"]["attributes"].get("name"))
    v = latest_version(tok, aid)
    if not v:
        print("no versions"); return
    vid = v["id"]
    print("version:", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
    s, b = jget("GET", f"/v1/appStoreVersions/{vid}/build", tok)
    bd = b.get("data") if isinstance(b, dict) else None
    print("build:", (bd["attributes"]["version"] + " " + bd["attributes"]["processingState"]) if bd else "none")


def cmd_set_metadata(a):
    tok = token(); aid = app_id(tok)
    v = latest_version(tok, aid); vid = v["id"]
    if os.environ.get("ASC_COPYRIGHT"):
        s, _ = call("PATCH", f"/v1/appStoreVersions/{vid}",
                    {"data": {"type": "appStoreVersions", "id": vid,
                              "attributes": {"copyright": os.environ["ASC_COPYRIGHT"]}}}, tok)
        print("copyright:", s)
    # privacyPolicyUrl lives on appInfoLocalization
    s, infos = jget("GET", f"/v1/apps/{aid}/appInfos", tok)
    info_id = infos["data"][0]["id"]
    s, locs = jget("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations", tok)
    if os.environ.get("ASC_PRIVACY_POLICY_URL"):
        lid = locs["data"][0]["id"]
        s, _ = call("PATCH", f"/v1/appInfoLocalizations/{lid}",
                    {"data": {"type": "appInfoLocalizations", "id": lid,
                              "attributes": {"privacyPolicyUrl": os.environ["ASC_PRIVACY_POLICY_URL"]}}}, tok)
        print("privacyPolicyUrl:", s)
    # support/marketing URLs on the version localization
    s, vlocs = jget("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", tok)
    attrs = {}
    if os.environ.get("ASC_SUPPORT_URL"): attrs["supportUrl"] = os.environ["ASC_SUPPORT_URL"]
    if os.environ.get("ASC_MARKETING_URL"): attrs["marketingUrl"] = os.environ["ASC_MARKETING_URL"]
    if attrs:
        vlid = vlocs["data"][0]["id"]
        s, _ = call("PATCH", f"/v1/appStoreVersionLocalizations/{vlid}",
                    {"data": {"type": "appStoreVersionLocalizations", "id": vlid, "attributes": attrs}}, tok)
        print("urls:", s)


def cmd_review_contact(a):
    tok = token(); aid = app_id(tok)
    v = latest_version(tok, aid); vid = v["id"]
    body = {"data": {"type": "appStoreReviewDetails",
            "attributes": {
                "contactFirstName": os.environ.get("ASC_CONTACT_FIRST", ""),
                "contactLastName": os.environ.get("ASC_CONTACT_LAST", ""),
                "contactPhone": os.environ.get("ASC_CONTACT_PHONE", ""),
                "contactEmail": os.environ.get("ASC_CONTACT_EMAIL", ""),
                "demoAccountRequired": False,
                "notes": os.environ.get("ASC_REVIEW_NOTES", "")},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}
    s, b = call("POST", "/v1/appStoreReviewDetails", body, tok)
    print("review-contact:", s, "" if s < 300 else b[:300])


def cmd_attach_build(a):
    tok = token(); aid = app_id(tok)
    v = latest_version(tok, aid); vid = v["id"]
    s, d = jget("GET", f"/v1/apps/{aid}/builds?limit=20", tok)
    target = next((x for x in d["data"] if str(x["attributes"]["version"]) == str(a.build)), None)
    if not target: sys.exit(f"build {a.build} not found")
    s, _ = call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                {"data": {"type": "builds", "id": target["id"]}}, tok)
    print("attach-build:", s)


def cmd_screenshots(a):
    tok = token(); aid = app_id(tok)
    v = latest_version(tok, aid); vid = v["id"]
    s, vlocs = jget("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", tok)
    loc = vlocs["data"][0]["id"]
    # find or create the set
    s, sets = jget("GET", f"/v1/appStoreVersionLocalizations/{loc}/appScreenshotSets", tok)
    setid = next((st["id"] for st in sets["data"]
                  if st["attributes"]["screenshotDisplayType"] == a.type), None)
    if not setid:
        s, b = call("POST", "/v1/appScreenshotSets",
                    {"data": {"type": "appScreenshotSets",
                              "attributes": {"screenshotDisplayType": a.type},
                              "relationships": {"appStoreVersionLocalization":
                                  {"data": {"type": "appStoreVersionLocalizations", "id": loc}}}}}, tok)
        setid = json.loads(b)["data"]["id"]
    print("set:", a.type, setid)
    for path in a.files:
        data = open(path, "rb").read(); name = os.path.basename(path)
        s, b = call("POST", "/v1/appScreenshots",
                    {"data": {"type": "appScreenshots",
                              "attributes": {"fileSize": len(data), "fileName": name},
                              "relationships": {"appScreenshotSet":
                                  {"data": {"type": "appScreenshotSets", "id": setid}}}}}, tok)
        if s >= 300: print("  reserve FAIL", s, b[:200]); continue
        d = json.loads(b)["data"]; sid = d["id"]
        op = d["attributes"]["uploadOperations"][0]
        req = urllib.request.Request(op["url"], data=data, method=op["method"])
        for h in op["requestHeaders"]: req.add_header(h["name"], h["value"])
        try:
            urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            print("  upload FAIL", e.code); continue
        md5 = hashlib.md5(data).hexdigest()
        s, _ = call("PATCH", f"/v1/appScreenshots/{sid}",
                    {"data": {"type": "appScreenshots", "id": sid,
                              "attributes": {"uploaded": True, "sourceFileChecksum": md5}}}, tok)
        print("  uploaded", name, s)


def cmd_submit(a):
    tok = token(); aid = app_id(tok)
    v = latest_version(tok, aid); vid = v["id"]
    s, b = call("POST", "/v1/reviewSubmissions",
                {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                          "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}, tok)
    if s >= 300: sys.exit("create submission failed: " + b[:300])
    sub = json.loads(b)["data"]["id"]
    s, b = call("POST", "/v1/reviewSubmissionItems",
                {"data": {"type": "reviewSubmissionItems",
                          "relationships": {
                              "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}, tok)
    if s >= 300:
        print("BLOCKED adding version:")
        try:
            for e in json.loads(b)["errors"]:
                for k, errs in e.get("meta", {}).get("associatedErrors", {}).items():
                    for er in errs: print("  -", er.get("code"), er.get("title"))
                if not e.get("meta"): print("  -", e.get("detail"))
        except Exception:
            print(b[:400])
        return
    s, b = call("PATCH", f"/v1/reviewSubmissions/{sub}",
                {"data": {"type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}}, tok)
    if s < 300:
        print("SUBMITTED:", json.loads(b)["data"]["attributes"].get("state"))
    else:
        print("submit failed:", s, b[:400])


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("set-metadata")
    sub.add_parser("review-contact")
    ab = sub.add_parser("attach-build"); ab.add_argument("--build", required=True)
    sc = sub.add_parser("screenshots")
    sc.add_argument("--type", required=True, help="e.g. APP_IPAD_PRO_3GEN_129, APP_IPHONE_65")
    sc.add_argument("files", nargs="+")
    sub.add_parser("submit")
    a = p.parse_args()
    {"status": cmd_status, "set-metadata": cmd_set_metadata, "review-contact": cmd_review_contact,
     "attach-build": cmd_attach_build, "screenshots": cmd_screenshots, "submit": cmd_submit}[a.cmd](a)


if __name__ == "__main__":
    main()
