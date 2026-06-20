# 6.9" App Store screenshots

`scripts/ci_submit.py` uploads the PNGs in this folder when it has to create a
*new* App Store version (so a fresh version still has screenshots). Apple uses
the 6.9"/6.7" iPhone display set for an iPad app via this slot — the
"iPhone-screenshot quirk" documented in the `app-store-submission` skill.

Commit 1–3 real 6.9" screenshots here (1290×2796 portrait or 2796×1290
landscape). The placeholder `docs/screenshots/*.png` are iPad-sized (2064×2752)
and are **not** valid for this slot.
