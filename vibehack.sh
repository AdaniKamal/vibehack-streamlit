#!/bin/bash

TARGET=$1
BOXNAME=$2

if [ -z "$TARGET" ] || [ -z "$BOXNAME" ]; then
  echo "Usage: ./vibehack.sh <target-ip> <box-name>"
  exit 1
fi

BASE="boxes/$BOXNAME"
mkdir -p $BASE/{nmap,web,loot,notes,screenshots}

echo "[+] Target: $TARGET"
echo "[+] Box: $BOXNAME"

echo "[+] Running basic Nmap scan..."
nmap -sC -sV -oN $BASE/nmap/basic.txt $TARGET

echo "[+] Running full port scan..."
nmap -p- --min-rate 5000 -oN $BASE/nmap/full_ports.txt $TARGET

PORTS=$(grep -oP '^[0-9]+(?=/tcp)' $BASE/nmap/full_ports.txt | paste -sd, -)

if [ ! -z "$PORTS" ]; then
  echo "[+] Running detailed scan on ports: $PORTS"
  nmap -sC -sV -p$PORTS -oN $BASE/nmap/detailed.txt $TARGET
fi

echo "[+] Checking common services..."

if grep -q "21/tcp" $BASE/nmap/detailed.txt; then
  echo "[FTP] Try: ftp $TARGET"
  echo "[FTP] Check anonymous login manually."
fi

if grep -q "22/tcp" $BASE/nmap/detailed.txt; then
  echo "[SSH] SSH found. Look for usernames/keys/password reuse."
fi

if grep -q "80/tcp\|443/tcp\|8080/tcp" $BASE/nmap/detailed.txt; then
  echo "[WEB] Web service found."
  echo "[+] Running whatweb..."
  whatweb http://$TARGET > $BASE/web/whatweb.txt 2>/dev/null

  echo "[+] Running directory brute force with common list..."
  gobuster dir -u http://$TARGET \
    -w /usr/share/wordlists/dirb/common.txt \
    -o $BASE/web/gobuster.txt
fi

if grep -q "2049/tcp" $BASE/nmap/detailed.txt; then
  echo "[NFS] Try manually:"
  echo "showmount -e $TARGET"
  echo "mkdir /tmp/nfs"
  echo "sudo mount -t nfs $TARGET:/share /tmp/nfs"
fi

if grep -q "445/tcp\|139/tcp" $BASE/nmap/detailed.txt; then
  echo "[SMB] Try manually:"
  echo "smbclient -L //$TARGET/ -N"
  echo "enum4linux-ng $TARGET"
fi

cat > $BASE/notes/checklist.md <<EOF
# $BOXNAME OSCP Checklist

## Target
- IP: $TARGET
- Platform:
- Difficulty:
- Date Started:

## Recon
- [ ] Nmap basic scan
- [ ] Full port scan
- [ ] Service enumeration
- [ ] Web enumeration
- [ ] SMB/FTP/NFS checked if available

## Initial Access
- [ ] Found possible vulnerability
- [ ] Verified manually
- [ ] Got shell

## Privilege Escalation
- [ ] Linux/Windows enum done
- [ ] Found privesc path
- [ ] Got root/admin

## Flags
- [ ] user.txt
- [ ] root.txt

## Notes
EOF

echo "[+] Done. Results saved in: $BASE"
