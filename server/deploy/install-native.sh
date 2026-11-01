#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo 'Run with sudo: sudo bash deploy/install-native.sh' >&2
    exit 1
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ $root != /opt/fly-sync/server ]]; then
    echo 'Upload the server folder to /opt/fly-sync/server first.' >&2
    exit 1
fi
cd "$root"
if [[ ! -f private/smtp.json ]]; then
    echo 'Upload your private SMTP config to server/private/smtp.json first.' >&2
    exit 1
fi
python3 -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11+ is required; Ubuntu 24.04 is recommended"'
if ! id fly-sync >/dev/null 2>&1; then
    useradd --system --user-group --home-dir /opt/fly-sync --shell /usr/sbin/nologin fly-sync
fi
chown -R -P fly-sync:fly-sync "$root"
chmod 700 private
chmod 600 private/smtp.json
if [[ ! -x .venv/bin/python ]]; then
    sudo -u fly-sync python3 -m venv .venv
fi
if [[ -d wheels ]]; then
    sudo -u fly-sync .venv/bin/python -m pip install --no-cache-dir --disable-pip-version-check --no-index --find-links wheels -r requirements.lock
else
    sudo -u fly-sync .venv/bin/python -m pip install --no-cache-dir --disable-pip-version-check -r requirements.lock
fi
if [[ ! -f .env ]]; then
    sudo -u fly-sync .venv/bin/python deploy/prepare_native.py
fi
chmod 600 .env
install -m 644 deploy/fly-sync.service /etc/systemd/system/fly-sync.service
systemctl daemon-reload
systemctl enable fly-sync
systemctl restart fly-sync
curl --fail --retry 8 --retry-connrefused --retry-delay 1 http://127.0.0.1:18766/api/health
printf '\nFly sync is running. Logs: sudo journalctl -u fly-sync -n 80 --no-pager\n'
