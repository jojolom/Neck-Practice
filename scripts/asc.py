# Minimal App Store Connect API client: python3 scripts/asc.py "/v1/apps"
# Reads key config from ~/.appstoreconnect/neck-practice.env (see upload-testflight.sh).
import base64, json, subprocess, time, os, sys, urllib.request
env = dict(l.strip().split("=",1) for l in open(os.path.expanduser("~/.appstoreconnect/neck-practice.env")) if "=" in l)
kid, iss = env["ASC_KEY_ID"], env["ASC_ISSUER_ID"]
key = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
now = int(time.time())
msg = b64(json.dumps({"alg":"ES256","kid":kid,"typ":"JWT"}).encode()) + b"." + b64(json.dumps({"iss":iss,"iat":now,"exp":now+600,"aud":"appstoreconnect-v1"}).encode())
der = subprocess.run(["openssl","dgst","-sha256","-sign",key], input=msg, capture_output=True, check=True).stdout
# DER ECDSA sig -> raw r||s
i = 2 if der[1] < 0x80 else 3
rl = der[i+1]; r = der[i+2:i+2+rl]; j = i+2+rl; sl = der[j+1]; s = der[j+2:j+2+sl]
raw = r.lstrip(b"\0").rjust(32,b"\0") + s.lstrip(b"\0").rjust(32,b"\0")
tok = (msg + b"." + b64(raw)).decode()
req = urllib.request.Request("https://api.appstoreconnect.apple.com" + sys.argv[1], headers={"Authorization": "Bearer " + tok})
try:
    print(urllib.request.urlopen(req).read().decode())
except urllib.error.HTTPError as e:
    print(e.code, e.read().decode())
