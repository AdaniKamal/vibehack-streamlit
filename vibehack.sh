#!/bin/bash

TARGET=$1
BOXNAME=$2

if [ -z "$TARGET" ] || [ -z "$BOXNAME" ]; then
  echo "Usage: ./vibehack.sh <target-ip> <box-name>"
  exit 1
fi

BASE="boxes/$BOXNAME"
WORDLIST_DIR="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"
ROCKYOU="./rockyou.txt"

mkdir -p "$BASE"/{nmap,ftp,web,smb,nfs,ssh,dns,snmp,rdp,db,udp,notes,loot,metasploit}

echo "======================================"
echo " VibeHack OSCP Lab Assistant"
echo " Target: $TARGET"
echo " Box: $BOXNAME"
echo "======================================"

echo ""
echo "[+] Running TCP full scan..."
nmap -sC -sV -O -p- -Pn "$TARGET" -oN "$BASE/nmap/tcp_full.txt"

echo ""
echo "========== TCP NMAP FINDINGS =========="
cat "$BASE/nmap/tcp_full.txt"
echo "======================================="

echo ""
read -p "Press ENTER to continue to UDP scan..."

echo ""
echo "[+] Running UDP scan..."
sudo nmap -sC -sV -sU -Pn "$TARGET" -oN "$BASE/nmap/udp_scan.txt"

echo ""
echo "========== UDP NMAP FINDINGS =========="
cat "$BASE/nmap/udp_scan.txt"
echo "======================================="

echo ""
read -p "Press ENTER to continue to service enumeration..."

TCP_PORTS=$(grep -oP '^[0-9]+(?=/tcp\s+open)' "$BASE/nmap/tcp_full.txt" | paste -sd, -)
UDP_PORTS=$(grep -oP '^[0-9]+(?=/udp\s+open)' "$BASE/nmap/udp_scan.txt" | paste -sd, -)

echo ""
echo "[+] Open TCP Ports: $TCP_PORTS"
echo "[+] Open UDP Ports: $UDP_PORTS"

has_tcp_port() {
  grep -q "^$1/tcp[[:space:]]\+open" "$BASE/nmap/tcp_full.txt"
}

has_udp_port() {
  grep -q "^$1/udp[[:space:]]\+open" "$BASE/nmap/udp_scan.txt"
}

write_note() {
  echo "$1" | tee -a "$BASE/notes/recommendations.md"
}

echo "# VibeHack Notes for $BOXNAME" > "$BASE/notes/recommendations.md"
echo "" >> "$BASE/notes/recommendations.md"
echo "Target: $TARGET" >> "$BASE/notes/recommendations.md"
echo "" >> "$BASE/notes/recommendations.md"

# =====================
# FTP ENUMERATION
# =====================
if has_tcp_port 21; then
  echo ""
  echo "========== FTP ENUMERATION =========="
  write_note "## FTP - Port 21"

  echo "[+] Testing anonymous FTP login..."
  {
    echo "anonymous"
    echo "anonymous"
    echo "pwd"
    echo "ls -la"
    echo "bye"
  } | ftp -inv "$TARGET" | tee "$BASE/ftp/anonymous_login.txt"

  echo "[+] Running FTP NSE scripts..."
  nmap -p21 --script "ftp-*" "$TARGET" -oN "$BASE/ftp/ftp_nse.txt"

  write_note "- Anonymous FTP tested. Check: $BASE/ftp/anonymous_login.txt"
  write_note "- FTP NSE scripts completed. Check: $BASE/ftp/ftp_nse.txt"
  write_note "- Manual commands:"
  write_note "  - ftp $TARGET"
  write_note "  - wget -m ftp://anonymous:anonymous@$TARGET"
  write_note "  - searchsploit vsftpd"
  write_note "  - If credentials are found elsewhere, test FTP login manually."
  write_note ""

  echo "[!] Hydra not run automatically."
  echo "    Lab-only manual example:"
  echo "    hydra -L users.txt -P rockyou.txt ftp://$TARGET"
fi

# =====================
# SSH ENUMERATION
# =====================
if has_tcp_port 22; then
  echo ""
  echo "========== SSH ENUMERATION =========="
  write_note "## SSH - Port 22"

  echo "[+] Running SSH NSE scripts..."
  nmap -p22 --script "ssh-*" "$TARGET" -oN "$BASE/ssh/ssh_nse.txt"

  write_note "- SSH NSE scripts completed. Check: $BASE/ssh/ssh_nse.txt"
  write_note "- Check for username reuse from FTP/Web/SMB."
  write_note "- If private key found, try:"
  write_note "  - chmod 600 id_rsa"
  write_note "  - ssh -i id_rsa user@$TARGET"
  write_note "- Manual version check:"
  write_note "  - searchsploit OpenSSH"
  write_note ""
fi

# =====================
# HTTP / HTTPS ENUMERATION
# =====================
for PORT in 80 443 8080 8000 8008 8888 8443; do
  if has_tcp_port "$PORT"; then
    echo ""
    echo "========== WEB ENUMERATION : PORT $PORT =========="

    if [ "$PORT" = "443" ] || [ "$PORT" = "8443" ]; then
      URL="https://$TARGET:$PORT"
    else
      URL="http://$TARGET:$PORT"
    fi

    WEBDIR="$BASE/web/$PORT"
    mkdir -p "$WEBDIR"

    write_note "## Web - Port $PORT"
    write_note "- URL: $URL"

    echo "[+] Running whatweb..."
    whatweb "$URL" | tee "$WEBDIR/whatweb.txt"

    echo "[+] Running curl headers..."
    curl -k -I "$URL" | tee "$WEBDIR/headers.txt"

    echo "[+] Running nikto..."
    nikto -h "$URL" -output "$WEBDIR/nikto.txt"

    echo "[+] Running gobuster..."
    gobuster dir \
      -u "$URL" \
      -w "$WORDLIST_DIR" \
      -k \
      -x php,txt,html,js,bak,old,zip \
      -o "$WEBDIR/gobuster.txt"

    echo "[+] Saving homepage..."
    curl -k "$URL" -o "$WEBDIR/homepage.html"

    write_note "- whatweb: $WEBDIR/whatweb.txt"
    write_note "- headers: $WEBDIR/headers.txt"
    write_note "- nikto: $WEBDIR/nikto.txt"
    write_note "- gobuster: $WEBDIR/gobuster.txt"
    write_note "- homepage saved: $WEBDIR/homepage.html"
    write_note "- Manual next checks:"
    write_note "  - View source code"
    write_note "  - Check robots.txt"
    write_note "  - Check /admin, /login, /backup, /uploads"
    write_note "  - Test default credentials manually"
    write_note "  - Use Burp Suite manually"
    write_note "  - If parameter found, test SQLi manually first"
    write_note "  - sqlmap lab-only example:"
    write_note "    sqlmap -u '$URL/page.php?id=1' --batch"
    write_note ""
  fi
done

# =====================
# SMB ENUMERATION
# =====================
if has_tcp_port 139 || has_tcp_port 445; then
  echo ""
  echo "========== SMB ENUMERATION =========="
  write_note "## SMB - Ports 139/445"

  enum4linux-ng "$TARGET" | tee "$BASE/smb/enum4linux-ng.txt"

  smbclient -L "//$TARGET/" -N | tee "$BASE/smb/smbclient_null.txt"

  nmap -p139,445 --script "smb-*" "$TARGET" -oN "$BASE/smb/smb_nse.txt"

  write_note "- enum4linux-ng completed."
  write_note "- smbclient null session tested."
  write_note "- SMB NSE scripts completed."
  write_note "- Manual commands:"
  write_note "  - smbclient -L //$TARGET/ -N"
  write_note "  - smbclient //$TARGET/share -N"
  write_note "  - crackmapexec smb $TARGET"
  write_note ""
fi

# =====================
# NFS ENUMERATION
# =====================
if has_tcp_port 2049; then
  echo ""
  echo "========== NFS ENUMERATION =========="
  write_note "## NFS - Port 2049"

  showmount -e "$TARGET" | tee "$BASE/nfs/showmount.txt"
  nmap -p2049 --script "nfs-*" "$TARGET" -oN "$BASE/nfs/nfs_nse.txt"

  write_note "- showmount completed."
  write_note "- NFS NSE scripts completed."
  write_note "- Manual mount example:"
  write_note "  - mkdir /tmp/nfs-$BOXNAME"
  write_note "  - sudo mount -t nfs $TARGET:/share /tmp/nfs-$BOXNAME -o nolock"
  write_note ""
fi

# =====================
# DNS ENUMERATION
# =====================
if has_tcp_port 53 || has_udp_port 53; then
  echo ""
  echo "========== DNS ENUMERATION =========="
  write_note "## DNS - Port 53"

  dig @"$TARGET" axfr | tee "$BASE/dns/zone_transfer.txt"
  nmap -p53 --script "dns-*" "$TARGET" -oN "$BASE/dns/dns_nse.txt"

  write_note "- Zone transfer attempted."
  write_note "- DNS NSE scripts completed."
  write_note "- Manual:"
  write_note "  - nslookup"
  write_note "  - dig @$TARGET domain.local axfr"
  write_note ""
fi

# =====================
# SNMP ENUMERATION
# =====================
if has_udp_port 161; then
  echo ""
  echo "========== SNMP ENUMERATION =========="
  write_note "## SNMP - UDP 161"

  snmpwalk -v2c -c public "$TARGET" | tee "$BASE/snmp/snmpwalk_public.txt"
  nmap -sU -p161 --script "snmp-*" "$TARGET" -oN "$BASE/snmp/snmp_nse.txt"

  write_note "- SNMP public community tested."
  write_note "- SNMP NSE scripts completed."
  write_note "- Check for usernames, processes, installed software."
  write_note ""
fi

# =====================
# RDP ENUMERATION
# =====================
if has_tcp_port 3389; then
  echo ""
  echo "========== RDP ENUMERATION =========="
  write_note "## RDP - Port 3389"

  nmap -p3389 --script "rdp-*" "$TARGET" -oN "$BASE/rdp/rdp_nse.txt"

  write_note "- RDP NSE scripts completed."
  write_note "- Manual:"
  write_note "  - xfreerdp /u:user /p:password /v:$TARGET"
  write_note ""
fi

# =====================
# DATABASE ENUMERATION
# =====================
if has_tcp_port 3306; then
  echo ""
  echo "========== MYSQL ENUMERATION =========="
  nmap -p3306 --script "mysql-*" "$TARGET" -oN "$BASE/db/mysql_nse.txt"
  write_note "## MySQL - Port 3306"
  write_note "- MySQL NSE scripts completed."
  write_note "- Manual: mysql -h $TARGET -u root -p"
  write_note ""
fi

if has_tcp_port 5432; then
  echo ""
  echo "========== POSTGRESQL ENUMERATION =========="
  nmap -p5432 --script "pgsql-*" "$TARGET" -oN "$BASE/db/postgres_nse.txt"
  write_note "## PostgreSQL - Port 5432"
  write_note "- PostgreSQL NSE scripts completed."
  write_note "- Manual: psql -h $TARGET -U postgres"
  write_note ""
fi

if has_tcp_port 1433; then
  echo ""
  echo "========== MSSQL ENUMERATION =========="
  nmap -p1433 --script "ms-sql-*" "$TARGET" -oN "$BASE/db/mssql_nse.txt"
  write_note "## MSSQL - Port 1433"
  write_note "- MSSQL NSE scripts completed."
  write_note "- Manual: impacket-mssqlclient user:pass@$TARGET"
  write_note ""
fi

# =====================
# LDAP / AD ENUMERATION
# =====================
if has_tcp_port 389 || has_tcp_port 636; then
  echo ""
  echo "========== LDAP / AD ENUMERATION =========="
  write_note "## LDAP / Active Directory"

  nmap -p389,636 --script "ldap-*" "$TARGET" -oN "$BASE/dns/ldap_nse.txt"

  write_note "- LDAP NSE scripts completed."
  write_note "- Manual:"
  write_note "  - ldapsearch -x -H ldap://$TARGET -s base"
  write_note "  - enum4linux-ng $TARGET"
  write_note ""
fi

# =====================
# METASPLOIT NOTES ONLY
# =====================
echo ""
echo "========== METASPLOIT CHECKLIST =========="
write_note "## Metasploit Manual Research"
write_note "- Use msfconsole for research only unless you intentionally test inside legal lab."
write_note "- Commands:"
write_note "  - msfconsole"
write_note "  - search type:auxiliary name:ftp"
write_note "  - search type:auxiliary name:smb"
write_note "  - searchsploit <service version>"
write_note ""

echo "[!] Metasploit modules are not executed automatically."
echo "    Recommended manual use:"
echo "    msfconsole"
echo "    search <service/version>"
echo "    info <module>"
echo "    check"

# =====================
# FINAL SUMMARY
# =====================
echo ""
echo "======================================"
echo " ENUMERATION COMPLETE"
echo " Results saved in: $BASE"
echo " Main notes: $BASE/notes/recommendations.md"
echo "======================================"

echo ""
echo "Open recommendations:"
echo "cat $BASE/notes/recommendations.md"
