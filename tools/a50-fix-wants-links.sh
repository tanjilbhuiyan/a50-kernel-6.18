#!/bin/sh
# Turn the four port "enable" entries that upstream commit 3f95df93 committed
# as plain text files back into the symlinks systemd requires.
set -eu
cd /etc/systemd/system
for p in multi-user.target.wants/a50-audio-hidl-compat.service \
         multi-user.target.wants/a50-audio-route.service \
         multi-user.target.wants/a50-gnss-unblock.service \
         repowerd.service.wants/a50-enable-autosuspend.service; do
    if [ -L "$p" ]; then echo "ok already: $p"; continue; fi
    t=$(cat "$p")
    case "$t" in ../a50-*.service) ;; *) echo "unexpected content in $p: $t" >&2; exit 1;; esac
    [ -f "${p%/*}/$t" ] || { echo "target missing for $p" >&2; exit 1; }
    rm "$p"; ln -s "$t" "$p"; echo "fixed: $p -> $t"
done
systemctl daemon-reload
for u in a50-audio-hidl-compat a50-audio-route a50-gnss-unblock a50-enable-autosuspend; do
    printf '%-26s %s\n' "$u" "$(systemctl is-enabled $u)"
done
echo "Done. Now reboot the phone."
