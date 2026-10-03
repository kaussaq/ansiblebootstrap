#!/bin/bash
# Usage: ./bootstrap.sh [-u username] <public-key.pub>
# Targets are read from hosts.txt next to this script, one user@host per line.
set -u

NEW_USER="awx"
while getopts u: opt; do
  case $opt in
    u) NEW_USER="$OPTARG" ;;
    *) exit 1 ;;
  esac
done
shift $((OPTIND - 1))

PUBKEY_FILE="${1:?usage: $0 [-u username] <public-key.pub>}"
HOSTS_FILE="$(dirname "$0")/hosts.txt"

[[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid username: $NEW_USER"; exit 1; }

KEY="$(head -n1 "$PUBKEY_FILE")"
[[ "$KEY" == ssh-* || "$KEY" == ecdsa-* || "$KEY" == sk-* ]] && [[ "$KEY" != *"'"* ]] \
  || { echo "Not a valid public key: $PUBKEY_FILE"; exit 1; }

REMOTE="KEY='$KEY'"$'\n'"NEW_USER='$NEW_USER'"$'\n'"$(cat <<'EOF'
set -e
if ! id "$NEW_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$NEW_USER"
  passwd -l "$NEW_USER" >/dev/null
fi
HOME_DIR="$(getent passwd "$NEW_USER" | cut -d: -f6)"
GRP="$(id -gn "$NEW_USER")"
install -d -m 700 -o "$NEW_USER" -g "$GRP" "$HOME_DIR/.ssh"
grep -qxF "$KEY" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null || echo "$KEY" >> "$HOME_DIR/.ssh/authorized_keys"
chown "$NEW_USER:$GRP" "$HOME_DIR/.ssh/authorized_keys"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"
TMP="$(mktemp)"
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > "$TMP"
visudo -cf "$TMP"
install -m 0440 -o root -g root "$TMP" "/etc/sudoers.d/$NEW_USER"
rm -f "$TMP"
EOF
)"
B64="$(printf '%s\n' "$REMOTE" | base64 | tr -d '\n')"

ok=(); failed=()

# fd 3 for the host list, because ssh would otherwise swallow stdin
while IFS= read -r target <&3; do
  target="${target//[[:space:]]/}"
  [[ -z "$target" || "$target" == \#* ]] && continue
  echo "=== $target ==="

  SUDO="sudo"
  [[ "${target%%@*}" == "root" ]] && SUDO=""

  if ssh -t -o StrictHostKeyChecking=accept-new "$target" \
      "t=\$(mktemp) && echo $B64 | base64 -d > \$t && $SUDO sh \$t; rc=\$?; rm -f \$t; exit \$rc"; then
    ok+=("$target")
  else
    failed+=("$target")
  fi
done 3< "$HOSTS_FILE"

echo; echo "OK:     ${ok[*]:-none}"
echo "FAILED: ${failed[*]:-none}"
