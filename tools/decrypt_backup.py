import subprocess
import base64
import gzip

with open('/home/alpha/backupsettings.conf', 'rb') as f:
    data = f.read()

b64_data = base64.b64encode(data).decode('ascii')

calix_cmd = f"""
cat << 'B64_END' | busybox base64 -d > /tmp/backupsettings.conf
{b64_data}
B64_END

tail -n +2 /tmp/backupsettings.conf > /tmp/backup.enc
/usr/bin/fencrypt -d /tmp/backup.enc /tmp/backup.dec 27885VT8118 2>/dev/null
if [ -s /tmp/backup.dec ]; then
    echo "===DEC_START==="
    busybox base64 /tmp/backup.dec
    echo "===DEC_END==="
else
    /usr/bin/fencrypt -d /tmp/backupsettings.conf /tmp/backup2.dec 27885VT8118 2>/dev/null
    if [ -s /tmp/backup2.dec ]; then
        echo "===DEC_START==="
        busybox base64 /tmp/backup2.dec
        echo "===DEC_END==="
    else
        echo "===FAILED==="
    fi
fi
"""

proc = subprocess.Popen(
    ["sshpass", "-p", "support", "ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "HostKeyAlgorithms=+ssh-rsa", "support@192.168.1.1"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)

out, err = proc.communicate(input=calix_cmd.encode('ascii'))
out_str = out.decode('latin1')

if "===DEC_START===" in out_str:
    part = out_str.split("===DEC_START===")[1].split("===DEC_END===")[0].strip()
    raw_dec = base64.b64decode(part)
    try:
        decompressed = gzip.decompress(raw_dec)
        final_text = decompressed.decode('utf-8', errors='replace')
    except Exception as e:
        final_text = raw_dec.decode('utf-8', errors='replace')
    
    with open('/home/alpha/decrypted_config.txt', 'w', encoding='utf-8') as f_out:
        f_out.write(final_text)
    print("SUCCESS: written to /home/alpha/decrypted_config.txt (length: %d)" % len(final_text))
    print("=== FIRST 50 LINES ===")
    lines = final_text.splitlines()
    for l in lines[:50]:
        print(l)
else:
    print("Failed to find markers in output:")
    print(out_str[:500])
