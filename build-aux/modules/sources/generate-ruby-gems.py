#!/usr/bin/env python3
"""Regenerate the gem source list and install order in modules/ruby-gnome.json.

Flatpak builds are offline, so every gem has to be listed as a `file` source and
installed with `gem install --local`. RubyGems will reach out to the network if a
dependency is missing, so the gems must also be installed in topological order.

Usage:
    ./generate-ruby-gems.py adwaita gtk4 gobject-introspection > /tmp/out.json
"""

import json
import sys
import urllib.request

API = "https://rubygems.org/api/v1/gems/{}.json"
DOWNLOAD = "https://rubygems.org/downloads/{}-{}.gem"

meta = {}


def walk(name):
    if name in meta:
        return
    with urllib.request.urlopen(API.format(name)) as response:
        data = json.load(response)
    meta[name] = {
        "version": data["version"],
        "sha256": data["sha"],
        "deps": [dep["name"] for dep in data["dependencies"]["runtime"]],
    }
    for dep in meta[name]["deps"]:
        walk(dep)


def toposort():
    order, done = [], set()

    def visit(name):
        if name in done:
            return
        done.add(name)
        for dep in sorted(meta[name]["deps"]):
            visit(dep)
        order.append(name)

    for name in sorted(meta):
        visit(name)
    return order


def main(roots):
    for root in roots:
        walk(root)
    order = toposort()

    gems = [f"{name}-{meta[name]['version']}.gem" for name in order]
    sources = [
        {
            "type": "file",
            "url": DOWNLOAD.format(name, meta[name]["version"]),
            "sha256": meta[name]["sha256"],
        }
        for name in order
    ]

    print(
        json.dumps(
            {
                "build-commands": [
                    "gem install --local --no-document --verbose "
                    + " \\\n    ".join(gems)
                ],
                "sources": sources,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main(sys.argv[1:] or ["adwaita", "gtk4", "gobject-introspection"])
