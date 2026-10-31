# Usage: python3 Scripts/make-country-db.py dbip-country-ipv4.csv dbip-country-ipv6.csv Sources/FreshetApp/Resources/countries.fcdb
# The CSVs come from the npm package @ip-location-db/dbip-country (DB-IP Lite, CC BY 4.0).
# Builds Freshet's country database from the DB-IP Lite CSVs.
# Format (all big-endian): b"FCDB" u16 version=1, u32 n4, u32 n6, then
#   n4 x (u32 start, 2-byte country) and n6 x (u64 start of the /64, 2-byte country).
# Ranges are contiguous: a gap is stored as country "--". Lookup = last start <= address.
import ipaddress, struct, sys
def load(path, v6):
    out = []
    for line in open(path):
        a, b, cc = line.strip().split(',')
        s, e = int(ipaddress.ip_address(a)), int(ipaddress.ip_address(b))
        if v6: s, e = s >> 64, e >> 64
        out.append((s, e, cc.encode()[:2]))
    return out
def compact(rows, maxv):
    res = []
    expect = 0
    for s, e, cc in rows:
        if s > expect: res.append((expect, b'--'))
        if res and res[-1][1] == cc: pass
        else:
            if res and res[-1][0] == s: res[-1] = (s, cc)
            else: res.append((max(s, expect) if not res or s >= expect else expect, cc))
        expect = max(expect, e + 1)
    if expect <= maxv: res.append((expect, b'--'))
    # merge equal neighbours
    merged = []
    for s, cc in res:
        if merged and merged[-1][1] == cc: continue
        merged.append((s, cc))
    return merged
v4 = compact(load(sys.argv[1], False), 0xffffffff)
v6 = compact(load(sys.argv[2], True), 0xffffffffffffffff)
with open(sys.argv[3], 'wb') as f:
    f.write(b'FCDB' + struct.pack('>HII', 1, len(v4), len(v6)))
    for s, cc in v4: f.write(struct.pack('>I', s) + cc)
    for s, cc in v6: f.write(struct.pack('>Q', s) + cc)
print(len(v4), len(v6))
