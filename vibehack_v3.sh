#!/bin/bash

TARGET=$1
BOXNAME=$2
MODE=$3

if [ -z "$TARGET" ] || [ -z "$BOXNAME" ]; then
  echo "Usage: ./vibehack.sh <target-ip> <box-name> [--fast]"
  exit 1
fi

BASE="boxes/$BOXNAME"
WEB_WORDLIST="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"
ROCKYOU="./rockyou.txt"

mkdir -p "$BASE"/{nmap,ftp,web,smb,nfs,ssh,dns,snmp,rdp,db,udp,notes,loot,metasploit}

NOTES="$BASE/notes/recommendations.md"

echo "# VibeHack Notes - $BOXNAME" > "$NOTES"
echo "" >> "$NOTES"
echo "- Target: $TARGET" >> "$NOTES"
echo "- Date: $(date)" >> "$NOTES"
echo "" >> "$NOTES"

write_note() {
  echo "$1" >> "$NOTES"
}

run_live() {
  TITLE="$1"
  OUTFILE="$2"
  shift 2

  TEMPLOG="/tmp/vibehack_live_$$.log"

  echo ""
  echo "=================================================="
  echo "$TITLE"
  echo "=================================================="
  echo "[+] Running: $*"
  echo ""

  "$@" 2>&1 | tee "$TEMPLOG"

  cp "$TEMPLOG" "$OUTFILE"
  rm -f "$TEMPLOG"

  echo ""
  echo "[+] Saved output to: $OUTFILE"
}

run_live_nmap() {
  TITLE="$1"
  OUTFILE="$2"
  shift 2

  echo ""
  echo "=================================================="
  echo "$TITLE"
  echo "=================================================="
  echo "[+] Running: nmap -vv $* -oN $OUTFILE"
  echo ""

  nmap -vv "$@" -oN "$OUTFILE"

  echo ""
  echo "[+] Saved clean Nmap output to: $OUTFILE"
}

has_tcp_port() {
  grep -q "^$1/tcp[[:space:]]\+open" "$BASE/nmap/tcp_full.txt"
}

has_udp_port() {
  grep -q "^$1/udp[[:space:]]\+open" "$BASE/nmap/udp_scan.txt"
}

echo "=================================================="
echo " VibeHack OSCP Lab Assistant"
echo " Target: $TARGET"
echo " Box: $BOXNAME"
echo "=================================================="

# ==================================================
# NMAP SCANS
# ==================================================

run_live_nmap "TCP FULL NMAP SCAN" "$BASE/nmap/tcp_full.txt" \
  -sC -sV -O -p- -Pn "$TARGET"

echo ""
echo "========== TCP NMAP FINDINGS =========="
cat "$BASE/nmap/tcp_full.txt"
echo "========================================"

read -p "Press ENTER to continue to UDP scan..."

if [ "$MODE" = "--fast" ]; then
  run_live_nmap "UDP FAST NMAP SCAN" "$BASE/nmap/udp_scan.txt" \
    -sC -sV -sU -Pn -p 53,67,68,69,123,137,138,161,162,500,514,520,631,1900,4500 "$TARGET"
else
  run_live_nmap "UDP FULL DEFAULT NMAP SCAN" "$BASE/nmap/udp_scan.txt" \
    -sC -sV -sU -Pn "$TARGET"
fi

echo ""
echo "========== UDP NMAP FINDINGS =========="
cat "$BASE/nmap/udp_scan.txt"
echo "========================================"

read -p "Press ENTER to continue to service enumeration..."

TCP_PORTS=$(grep -oP '^[0-9]+(?=/tcp\s+open)' "$BASE/nmap/tcp_full.txt" | paste -sd, -)
UDP_PORTS=$(grep -oP '^[0-9]+(?=/udp\s+open)' "$BASE/nmap/udp_scan.txt" | paste -sd, -)

echo ""
echo "[+] Open TCP Ports: $TCP_PORTS"
echo "[+] Open UDP Ports: $UDP_PORTS"

write_note "## Open Ports"
write_note ""
write_note "- TCP: $TCP_PORTS"
write_note "- UDP: $UDP_PORTS"
write_note ""

# ==================================================
# FTP ENUMERATION
# ==================================================

if has_tcp_port 21; then
  echo ""
  echo "========== FTP ENUMERATION =========="

  write_note "## FTP - Port 21"
  write_note ""

  run_live "FTP ANONYMOUS LOGIN TEST" "$BASE/ftp/anonymous_login.txt" \
    bash -c "echo -e 'anonymous\nanonymous\npwd\nls -la\nbye' | ftp -inv $TARGET"

  run_live_nmap "FTP NSE SCRIPTS" "$BASE/ftp/ftp_nse.txt" \
    -p21 --script "ftp-*" "$TARGET"

  run_live "FTP BANNER GRAB" "$BASE/ftp/banner.txt" \
    bash -c "echo quit | nc -nv $TARGET 21"

  write_note "- Anonymous login tested: $BASE/ftp/anonymous_login.txt"
  write_note "- FTP NSE completed: $BASE/ftp/ftp_nse.txt"
  write_note "- FTP banner saved: $BASE/ftp/banner.txt"
  write_note ""
  write_note "Manual FTP next steps:"
  write_note '```bash'
  write_note "ftp $TARGET"
  write_note "wget -m ftp://anonymous:anonymous@$TARGET"
  write_note "searchsploit vsftpd"
  write_note "hydra -L users.txt -P rockyou.txt ftp://$TARGET"
  write_note '```'
  write_note ""
fi

# ==================================================
# SSH ENUMERATION
# ==================================================

if has_tcp_port 22; then
  echo ""
  echo "========== SSH ENUMERATION =========="

  write_note "## SSH - Port 22"
  write_note ""

  run_live_nmap "SSH NSE SCRIPTS" "$BASE/ssh/ssh_nse.txt" \
    -p22 --script "ssh-*" "$TARGET"

  run_live "SSH BANNER GRAB" "$BASE/ssh/banner.txt" \
    bash -c "echo quit | nc -nv $TARGET 22"

  write_note "- SSH NSE completed: $BASE/ssh/ssh_nse.txt"
  write_note "- SSH banner saved: $BASE/ssh/banner.txt"
  write_note ""
  write_note "Manual SSH next steps:"
  write_note '```bash'
  write_note "searchsploit OpenSSH"
  write_note "ssh user@$TARGET"
  write_note "ssh -i id_rsa user@$TARGET"
  write_note '```'
  write_note ""
fi

# ==================================================
# HTTP / HTTPS ENUMERATION
# ==================================================

for PORT in 80 443 8080 8000 8008 8888 8443 3000 5000 9000; do
  if has_tcp_port "$PORT"; then

    if [ "$PORT" = "443" ] || [ "$PORT" = "8443" ]; then
      URL="https://$TARGET:$PORT"
    else
      URL="http://$TARGET:$PORT"
    fi

    WEBDIR="$BASE/web/$PORT"
    mkdir -p "$WEBDIR"

    echo ""
    echo "========== WEB ENUMERATION : $URL =========="

    write_note "## Web - Port $PORT"
    write_note ""
    write_note "- URL: $URL"
    write_note ""

    run_live "WHATWEB PORT $PORT" "$WEBDIR/whatweb.txt" \
      whatweb -v "$URL"

    run_live "CURL HEADERS PORT $PORT" "$WEBDIR/headers.txt" \
      curl -k -I "$URL"

    run_live "CURL HOMEPAGE PORT $PORT" "$WEBDIR/homepage.html" \
      curl -k "$URL"

    run_live "ROBOTS.TXT PORT $PORT" "$WEBDIR/robots.txt" \
      curl -k "$URL/robots.txt"

    run_live "NIKTO PORT $PORT" "$WEBDIR/nikto.txt" \
      nikto -h "$URL"

    run_live "GOBUSTER PORT $PORT" "$WEBDIR/gobuster.txt" \
      gobuster dir \
        -u "$URL" \
        -w "$WEB_WORDLIST" \
        -k \
        -x php,txt,html,js,bak,old,zip,conf \
        -t 30

    write_note "- whatweb: $WEBDIR/whatweb.txt"
    write_note "- headers: $WEBDIR/headers.txt"
    write_note "- homepage: $WEBDIR/homepage.html"
    write_note "- robots.txt: $WEBDIR/robots.txt"
    write_note "- nikto: $WEBDIR/nikto.txt"
    write_note "- gobuster: $WEBDIR/gobuster.txt"
    write_note ""
    write_note "Manual Web next steps:"
    write_note '```bash'
    write_note "curl -k -I $URL"
    write_note "curl -k $URL"
    write_note "feroxbuster -u $URL -w $WEB_WORDLIST -k"
    write_note "wpscan --url $URL --disable-tls-checks"
    write_note "sqlmap -u '$URL/page.php?id=1' --batch"
    write_note '```'
    write_note ""
  fi
done

# ==================================================
# SMB ENUMERATION
# ==================================================

if has_tcp_port 139 || has_tcp_port 445; then
  echo ""
  echo "========== SMB ENUMERATION =========="

  write_note "## SMB - Ports 139/445"
  write_note ""

  run_live "ENUM4LINUX-NG" "$BASE/smb/enum4linux-ng.txt" \
    enum4linux-ng "$TARGET"

  run_live "SMBCLIENT NULL SESSION" "$BASE/smb/smbclient_null.txt" \
    smbclient -L "//$TARGET/" -N

  run_live_nmap "SMB NSE SCRIPTS" "$BASE/smb/smb_nse.txt" \
    -p139,445 --script "smb-*" "$TARGET"

  write_note "- enum4linux-ng: $BASE/smb/enum4linux-ng.txt"
  write_note "- smbclient null: $BASE/smb/smbclient_null.txt"
  write_note "- SMB NSE: $BASE/smb/smb_nse.txt"
  write_note ""
  write_note "Manual SMB next steps:"
  write_note '```bash'
  write_note "smbclient -L //$TARGET/ -N"
  write_note "smbclient //$TARGET/share -N"
  write_note "crackmapexec smb $TARGET"
  write_note "crackmapexec smb $TARGET --shares"
  write_note '```'
  write_note ""
fi

# ==================================================
# NFS ENUMERATION
# ==================================================

if has_tcp_port 2049; then
  echo ""
  echo "========== NFS ENUMERATION =========="

  write_note "## NFS - Port 2049"
  write_note ""

  run_live "SHOWMOUNT" "$BASE/nfs/showmount.txt" \
    showmount -e "$TARGET"

  run_live_nmap "NFS NSE SCRIPTS" "$BASE/nfs/nfs_nse.txt" \
    -p2049 --script "nfs-*" "$TARGET"

  write_note "- showmount: $BASE/nfs/showmount.txt"
  write_note "- NFS NSE: $BASE/nfs/nfs_nse.txt"
  write_note ""
  write_note "Manual NFS next steps:"
  write_note '```bash'
  write_note "mkdir /tmp/nfs-$BOXNAME"
  write_note "sudo mount -t nfs $TARGET:/share /tmp/nfs-$BOXNAME -o nolock"
  write_note "ls -la /tmp/nfs-$BOXNAME"
  write_note '```'
  write_note ""
fi

# ==================================================
# DNS ENUMERATION
# ==================================================

if has_tcp_port 53 || has_udp_port 53; then
  echo ""
  echo "========== DNS ENUMERATION =========="

  write_note "## DNS - Port 53"
  write_note ""

  run_live "DNS BASIC QUERY" "$BASE/dns/basic_query.txt" \
    dig @"$TARGET"

  run_live "DNS ZONE TRANSFER ATTEMPT" "$BASE/dns/zone_transfer.txt" \
    dig @"$TARGET" axfr

  run_live_nmap "DNS NSE SCRIPTS" "$BASE/dns/dns_nse.txt" \
    -p53 --script "dns-*" "$TARGET"

  write_note "- DNS basic query: $BASE/dns/basic_query.txt"
  write_note "- Zone transfer attempt: $BASE/dns/zone_transfer.txt"
  write_note "- DNS NSE: $BASE/dns/dns_nse.txt"
  write_note ""
fi

# ==================================================
# SNMP ENUMERATION
# ==================================================

if has_udp_port 161; then
  echo ""
  echo "========== SNMP ENUMERATION =========="

  write_note "## SNMP - UDP 161"
  write_note ""

  run_live "SNMPWALK PUBLIC" "$BASE/snmp/snmpwalk_public.txt" \
    snmpwalk -v2c -c public "$TARGET"

  run_live_nmap "SNMP NSE SCRIPTS" "$BASE/snmp/snmp_nse.txt" \
    -sU -p161 --script "snmp-*" "$TARGET"

  write_note "- snmpwalk public: $BASE/snmp/snmpwalk_public.txt"
  write_note "- SNMP NSE: $BASE/snmp/snmp_nse.txt"
  write_note ""
fi

# ==================================================
# RDP ENUMERATION
# ==================================================

if has_tcp_port 3389; then
  echo ""
  echo "========== RDP ENUMERATION =========="

  write_note "## RDP - Port 3389"
  write_note ""

  run_live_nmap "RDP NSE SCRIPTS" "$BASE/rdp/rdp_nse.txt" \
    -p3389 --script "rdp-*" "$TARGET"

  write_note "- RDP NSE: $BASE/rdp/rdp_nse.txt"
  write_note ""
  write_note "Manual RDP next steps:"
  write_note '```bash'
  write_note "xfreerdp /u:user /p:password /v:$TARGET"
  write_note '```'
  write_note ""
fi

# ==================================================
# MYSQL ENUMERATION
# ==================================================

if has_tcp_port 3306; then
  echo ""
  echo "========== MYSQL ENUMERATION =========="

  write_note "## MySQL - Port 3306"
  write_note ""

  run_live_nmap "MYSQL NSE SCRIPTS" "$BASE/db/mysql_nse.txt" \
    -p3306 --script "mysql-*" "$TARGET"

  write_note "- MySQL NSE: $BASE/db/mysql_nse.txt"
  write_note ""
  write_note "Manual MySQL next steps:"
  write_note '```bash'
  write_note "mysql -h $TARGET -u root -p"
  write_note '```'
  write_note ""
fi

# ==================================================
# POSTGRESQL ENUMERATION
# ==================================================

if has_tcp_port 5432; then
  echo ""
  echo "========== POSTGRESQL ENUMERATION =========="

  write_note "## PostgreSQL - Port 5432"
  write_note ""

  run_live_nmap "POSTGRESQL NSE SCRIPTS" "$BASE/db/postgres_nse.txt" \
    -p5432 --script "pgsql-*" "$TARGET"

  write_note "- PostgreSQL NSE: $BASE/db/postgres_nse.txt"
  write_note ""
fi

# ==================================================
# MSSQL ENUMERATION
# ==================================================

if has_tcp_port 1433; then
  echo ""
  echo "========== MSSQL ENUMERATION =========="

  write_note "## MSSQL - Port 1433"
  write_note ""

  run_live_nmap "MSSQL NSE SCRIPTS" "$BASE/db/mssql_nse.txt" \
    -p1433 --script "ms-sql-*" "$TARGET"

  write_note "- MSSQL NSE: $BASE/db/mssql_nse.txt"
  write_note ""
fi

# ==================================================
# LDAP / ACTIVE DIRECTORY ENUMERATION
# ==================================================

if has_tcp_port 389 || has_tcp_port 636; then
  echo ""
  echo "========== LDAP / ACTIVE DIRECTORY ENUMERATION =========="

  write_note "## LDAP / Active Directory"
  write_note ""

  run_live_nmap "LDAP NSE SCRIPTS" "$BASE/dns/ldap_nse.txt" \
    -p389,636 --script "ldap-*" "$TARGET"

  run_live "LDAP BASE QUERY" "$BASE/dns/ldap_base.txt" \
    ldapsearch -x -H "ldap://$TARGET" -s base

  write_note "- LDAP NSE: $BASE/dns/ldap_nse.txt"
  write_note "- LDAP base query: $BASE/dns/ldap_base.txt"
  write_note ""
fi

# ==================================================
# METASPLOIT NOTES ONLY
# ==================================================

echo ""
echo "========== METASPLOIT MANUAL CHECKLIST =========="

write_note "## Metasploit Manual Research"
write_note ""
write_note "Use Metasploit manually only inside legal labs."
write_note ""
write_note '```bash'
write_note "msfconsole"
write_note "search type:auxiliary ftp"
write_note "search type:auxiliary smb"
write_note "search type:auxiliary ssh"
write_note "search <service version>"
write_note "info <module>"
write_note "check"
write_note '```'
write_note ""

echo "[!] Metasploit modules are not executed automatically."
echo "[!] Hydra and sqlmap are not executed automatically."
echo "[+] Manual commands are written in: $NOTES"

# ==================================================
# FINAL SUMMARY
# ==================================================

echo ""
echo "=================================================="
echo " ENUMERATION COMPLETE"
echo "=================================================="
echo "[+] Results saved in: $BASE"
echo "[+] Main notes: $NOTES"
echo ""
echo "View recommendations:"
echo "cat $NOTES"
echo "=================================================="
