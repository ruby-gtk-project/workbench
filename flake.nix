{
  description = "Workbench — development shell for the Ruby language support";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          inherit (pkgs) lib;

          # Match build-aux/modules/ruby.json, so what works here has a fair
          # chance of working in the Flatpak.
          ruby = pkgs.ruby_4_0;

          # Libraries the previewer reaches through GObject Introspection.
          # Mirrors the gi.require_version() calls at the top of
          # src/langs/python/python-previewer.py.
          gi-libraries = with pkgs; [
            glib
            gtk4
            libadwaita
            gtksourceview5
            graphene
            gdk-pixbuf
            pango
            cairo
            harfbuzz
            libshumate
            webkitgtk_6_0
          ];

          # Native headers the ruby-gnome gems compile against.
          #
          # libsysprof-capture is not needed to *link*, but the pkg-config gem
          # resolves Requires.private transitively and glib.pc names
          # sysprof-capture-4. Nixpkgs keeps that .pc in its own package rather
          # than propagating it from glib, so the glib2 gem's extconf.rb fails
          # without it. The GNOME SDK ships it in the runtime, so this is a
          # devshell-only concern.
          native-deps = with pkgs; [
            gobject-introspection
            atk
            libyaml
            openssl
            zlib
            libffi
            libsysprof-capture
          ]
          ++ pkg-config-closure;

          # The pkg-config gem walks Requires.private transitively and dies on
          # the first .pc it cannot find. Nixpkgs splits these across many
          # packages instead of propagating them from glib/gtk4/pango, so the
          # whole closure has to be on PKG_CONFIG_PATH explicitly. None of this
          # is needed in the Flatpak, where the SDK is one flat prefix.
          pkg-config-closure =
            (with pkgs; [
              pcre2
              libepoxy
              fribidi
              libpng
              fontconfig
              freetype
              expat
              util-linux
              libselinux
              libsepol
              wayland
              libxkbcommon
              libdrm
              libthai
              libdatrie
              libglvnd
              libxml2
              sqlite
              icu
              brotli
              libwebp
              libtiff
              libjpeg
              zstd
              bzip2
              libxslt
              lerc
              libdeflate
              xz
              libxcb
            ])
            ++ (with pkgs; [
              libx11
              libxext
              libxi
              libxrandr
              libxcursor
              libxfixes
              libxdamage
              libxinerama
              libxrender
              libxtst
              libxau
              libxdmcp
              xorgproto
            ]);
        in
        {
          default = pkgs.mkShell {
            name = "workbench-ruby";

            nativeBuildInputs = with pkgs; [
              pkg-config
              ruby
              ruby-lsp

              # Workbench itself
              gjs
              meson
              ninja
              blueprint-compiler
              desktop-file-utils
              appstream
              gettext

              # build-aux/modules/sources/generate-ruby-gems.py, manifests
              python3
              jq

              flatpak-builder
            ];

            buildInputs = gi-libraries ++ native-deps;

            shellHook = ''
              # Gems install into the checkout, not into ~/.gem, so the tree
              # stays self-contained and disposable.
              export GEM_HOME="$PWD/.gems/${ruby.version}"
              export GEM_PATH="$GEM_HOME"
              export PATH="$GEM_HOME/bin:$PATH"

              # GI needs both the typelibs and the shared objects they name.
              export GI_TYPELIB_PATH="${
                lib.makeSearchPathOutput "out" "lib/girepository-1.0" gi-libraries
              }''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
              export LD_LIBRARY_PATH="${
                lib.makeLibraryPath (gi-libraries ++ native-deps)
              }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

              # Without the schemas, Gtk.init aborts at runtime.
              export XDG_DATA_DIRS="${
                lib.concatMapStringsSep ":" (p: "${p}/share") [
                  pkgs.gsettings-desktop-schemas
                  pkgs.gtk4
                  pkgs.libadwaita
                  pkgs.adwaita-icon-theme
                  pkgs.shared-mime-info
                ]
              }''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

              echo "workbench ruby devshell"
              echo "  ruby       $(ruby --version | cut -d' ' -f2)"
              echo "  gems       $GEM_HOME"
              echo
              if [ ! -d "$GEM_HOME/gems" ]; then
                echo "  gems are not installed yet — run:"
                echo "    ./nix/install-ruby-gems.sh"
                echo
              fi
            '';
          };
        }
      );
    };
}
