#!/usr/bin/env bash
# Install the ruby-gnome gems into the devshell's GEM_HOME.
#
# Versions come from build-aux/modules/ruby-gnome.json so that local
# development tracks whatever the Flatpak actually ships — there is one source
# of truth for the gem set, and it is the manifest.
#
# Unlike the Flatpak build this one is online: it resolves from rubygems.org
# rather than from pinned .gem files.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/build-aux/modules/ruby-gnome.json"

if [ -z "${GEM_HOME:-}" ]; then
  echo "GEM_HOME is unset — run this inside 'nix develop'." >&2
  exit 1
fi

mapfile -t gems < <(
  python3 - "$manifest" <<'PY'
import json
import sys

with open(sys.argv[1]) as manifest:
    module = json.load(manifest)

for source in module["sources"]:
    url = source.get("url")
    if not url or not url.endswith(".gem"):
        continue
    name, _, version = url.rsplit("/", 1)[-1][: -len(".gem")].rpartition("-")
    print(f"{name}:{version}")
PY
)

echo "installing ${#gems[@]} gems into $GEM_HOME"
gem install --no-document "${gems[@]}"

echo
ruby -e 'require "gtk4"; require "adwaita"; puts "ruby-gnome loads"'
