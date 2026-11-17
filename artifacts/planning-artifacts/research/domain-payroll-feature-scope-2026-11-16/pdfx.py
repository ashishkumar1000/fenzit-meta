import re, sys, zlib

path = sys.argv[1]
raw = open(path, 'rb').read()
out = []
for m in re.finditer(rb'stream\r?\n(.*?)endstream', raw, re.S):
    data = m.group(1)
    try:
        data = zlib.decompress(data)
    except Exception:
        continue
    # extract text in Tj / TJ operators
    txt = []
    for t in re.finditer(rb'\((.*?)\)\s*Tj', data, re.S):
        txt.append(t.group(1).decode('latin-1'))
    for t in re.finditer(rb'\[(.*?)\]\s*TJ', data, re.S):
        parts = re.findall(rb'\((.*?)\)', t.group(1), re.S)
        txt.append(b''.join(parts).decode('latin-1'))
    if txt:
        s = ' '.join(txt)
        s = s.replace('\\(', '(').replace('\\)', ')')
        out.append(s)
print('\n---PAGE---\n'.join(out)[:120000])
