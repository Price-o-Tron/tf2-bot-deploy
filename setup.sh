#!/usr/bin/env bash
# One-time setup for the Price-o-Tron bot stack: HTTPS + firewall.
#
#   ./setup.sh                    free hostname from this server's public IP (sslip.io)
#   ./setup.sh bot.example.com    your own domain (its DNS A record must point at this server)
#
# Options:
#   --yes, -y        do not ask before changing the firewall
#   --no-firewall    skip the firewall step (cloud firewall / router handles it)
#
# Needs: Docker with Compose, ports 80 and 443 reachable from the internet.
# Price-o-Tron only connects to bots over HTTPS, so this setup is required.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

say()  { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

DOMAIN=""
ASSUME_YES=0
FIREWALL=1
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    --no-firewall) FIREWALL=0 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) fail "Unknown option: $arg" ;;
    *) DOMAIN="$arg" ;;
  esac
done

command -v docker >/dev/null || fail "Docker is not installed."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required ('docker compose')."
[ -f .env ] || fail "No .env yet. Copy template.env to .env and fill it in first (see README), then run this again."

public_ip() {
  local ip url
  for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip="$(curl -4fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')" || continue
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then printf '%s' "$ip"; return 0; fi
  done
  return 1
}

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  [ -t 0 ] || fail "Not running in a terminal. Re-run with --yes to allow the firewall changes, or with --no-firewall."
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------- firewall (ufw)
ssh_ports() {
  local ports="" session_port
  # the port this very SSH session came in on, so we never lock the user out
  session_port="${SSH_CONNECTION##* }"
  [[ "${SSH_CONNECTION:-}" && "$session_port" =~ ^[0-9]+$ ]] && ports="$session_port"
  if command -v ss >/dev/null; then
    ports="$ports $($SUDO ss -tlnpH 2>/dev/null | grep -w sshd | awk '{print $4}' | sed 's/.*://' || true)"
  fi
  ports="$(printf '%s\n' $ports | grep -E '^[0-9]+$' | sort -un | tr '\n' ' ')"
  printf '%s' "${ports:-22}"
}

setup_firewall() {
  [ "$(uname -s)" = Linux ] || { say "Skipping firewall: only supported on Linux. Make sure TCP 80, TCP/UDP 443 are reachable."; return 0; }

  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null || { say "Skipping firewall: needs root and sudo was not found. Open TCP 80, TCP/UDP 443 yourself."; return 0; }
    SUDO="sudo"
  fi

  local have_ufw=1 ssh active
  command -v ufw >/dev/null || have_ufw=0
  if [ "$have_ufw" = 0 ] && ! command -v apt-get >/dev/null; then
    say "Skipping firewall: ufw can only be installed automatically on Debian/Ubuntu. Open TCP 80, TCP/UDP 443 with your firewall."
    return 0
  fi

  ssh="$(ssh_ports)"
  say ""
  say "Firewall (ufw) - this will:"
  [ "$have_ufw" = 0 ] && say "  - install ufw (apt-get install ufw)"
  say "  - allow SSH on port(s): $ssh   (so you are not locked out)"
  say "  - allow 80/tcp, 443/tcp and 443/udp for HTTPS"
  say "  - enable ufw if it is not active yet (incoming traffic is denied unless allowed)"
  confirm "Continue?" || { say "Skipping firewall. Open TCP 80, TCP/UDP 443 yourself."; return 0; }

  if [ "$have_ufw" = 0 ]; then
    $SUDO apt-get update -qq
    $SUDO apt-get install -y ufw
  fi

  local p
  for p in $ssh; do $SUDO ufw allow "$p/tcp" comment 'SSH' >/dev/null; done
  $SUDO ufw allow 80/tcp comment 'Price-o-Tron HTTP (certificate)' >/dev/null
  $SUDO ufw allow 443/tcp comment 'Price-o-Tron HTTPS' >/dev/null
  $SUDO ufw allow 443/udp comment 'Price-o-Tron HTTP/3' >/dev/null

  active="$($SUDO ufw status | head -n1 || true)"
  case "$active" in
    *inactive*) $SUDO ufw --force enable >/dev/null; say "ufw enabled." ;;
    *) say "ufw was already active; rules added." ;;
  esac

  say "Note: ports published by Docker (like 8080) bypass ufw. Behind a home router you also need"
  say "      to forward ports 80 and 443 to this machine."
}

if [ "$FIREWALL" = 1 ]; then setup_firewall; else say "Skipping firewall (--no-firewall)."; fi

# ---------------------------------------------------------------- domain
if [ -z "$DOMAIN" ]; then
  IP="$(public_ip)" || fail "Could not detect this server's public IP. Pass a domain instead: ./setup.sh bot.example.com"
  DOMAIN="${IP//./-}.sslip.io"
  say ""
  say "No domain given. Using the free hostname $DOMAIN (it always points at $IP)."
fi

DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || fail "'$DOMAIN' is not a valid domain name."

# Custom domains: warn early if DNS does not point here yet (Let's Encrypt would fail).
if [[ "$DOMAIN" != *.sslip.io ]] && command -v dig >/dev/null; then
  RESOLVED="$(dig +short A "$DOMAIN" | tail -n1)"
  HERE="$(public_ip || true)"
  if [ -z "$RESOLVED" ]; then
    say "Warning: $DOMAIN has no DNS A record yet. Create one pointing at ${HERE:-this server}; the certificate cannot be issued until it does."
  elif [ -n "$HERE" ] && [ "$RESOLVED" != "$HERE" ]; then
    say "Warning: $DOMAIN points at $RESOLVED but this server is $HERE. The certificate will fail until DNS matches."
  fi
fi

# Save BOT_DOMAIN in .env (replace the line if present, otherwise append).
TMP="$(mktemp)"
grep -v '^BOT_DOMAIN=' .env > "$TMP" || true
printf 'BOT_DOMAIN="%s"\n' "$DOMAIN" >> "$TMP"
cat "$TMP" > .env
rm -f "$TMP"

# ---------------------------------------------------------------- start
say ""
say "Starting the stack..."
docker compose up -d

say "Waiting for the certificate (can take up to a minute)..."
for _ in $(seq 1 30); do
  code="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "https://$DOMAIN/" 2>/dev/null || true)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    say ""
    say "Done. Your bot app is served over HTTPS at: https://$DOMAIN"
    say "Enter exactly this address in Price-o-Tron: Profile -> Bot Server Address."
    exit 0
  fi
  sleep 2
done

say ""
say "The stack is running, but https://$DOMAIN is not answering yet."
say "Check that ports 80 and 443 are open to the internet, then look at: docker compose logs caddy"
exit 1
