#!/usr/bin/env bash
# Census the translatable messages in a source tree, one row per message.
#
# Output: <msgctxt>\t<msgid>\t<kind>\t<file>:<line>
#         msgctxt is `-` when the message has none.
#
# The (msgctxt, msgid) pair is gettext's lookup key, so it is the unit here -
# not the source line, not the .po entry. Two calls to _("Cancel") in two files
# are one message and one row; C_("shortcut window", "Help") and _("Help") are
# two messages that a human reader would call the same string.
#
# `kind` says which marker produced the row, so a message that is plural
# upstream and singular in the port shows up as a difference on a key that
# otherwise matches:
#
#   single   _("...")            N_("...")          translatable="yes"
#   plural   ngettext(a, b, n)   n_(a, b, n)        Nn_ / np_
#   po       an msgid already in po/*.po - what translators have been given
#
# Usage: msgid-census.sh <tree> [more-trees...]
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $(basename "$0") <tree>..." >&2; exit 2; }

# A string is translatable only if a marker wraps it, so there is no file-type
# gate here the way there is in test-census.sh - every file that can hold a
# marker is read, and files that hold none cost nothing.
sources() {
  find "$1" -type f \
    -not -path '*/.git/*' -not -path '*/_build/*' -not -path '*/build/*' \
    -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' \
    -not -path '*/.claude/skills/*' -not -path '*/target/*' \
    \( -name '*.vala' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' \
       -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rs' \
       -o -name '*.rb' -o -name '*.blp' -o -name '*.ui' -o -name '*.xml' \
       -o -name '*.xml.in' -o -name '*.xml.in.in' \
       -o -name '*.desktop.in' -o -name '*.desktop.in.in' -o -name '*.desktop' \
       -o -name '*.ui.in' \
       -o -name '*.po' -o -name '*.pot' \) 2>/dev/null
}

# The marker scanner. Separated out so the two comment dialects share it.
#
# Works on a joined buffer of the current line plus the next few, because a
# marker's msgid routinely lives on a different line from the marker:
#
#     error_body = g_strdup_printf (C_("spad-message",
#                                      "The link "<a href=\"%s\">%s</a>" uses "
#                                      "the protocol "%s", for which no apps "
#                                      ...
#
# and because C concatenates adjacent literals, so the msgid there is four
# source literals. A line-at-a-time scan reports that call as unresolved and
# kgx loses twelve of its messages that way. Matches are only reported when
# they *start* on the current line, so the window never double-counts.
markers_awk() {
  awk -v F="$2" -v LANG_KIND="$3" '
    BEGIN {
      Q  = sprintf("%c", 39)
      DQ = "^[[:space:]]*\"([^\"\\\\]|\\\\.)*\""
      SQ = "^[[:space:]]*" Q "([^" Q "\\\\]|\\\\.)*" Q
      LOOKAHEAD = 6
    }

    # Take the leading string literal of s, in either quote style, absorbing
    # any literals adjacent to it. Sets LIT and LITREST.
    function take_lit(s,   m, q, out, got) {
      out = ""; got = 0
      while (1) {
        if (match(s, DQ)) q = "\""
        else if (match(s, SQ)) q = Q
        else break
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        sub("^[[:space:]]*" q, "", m)
        sub(q "$", "", m)
        out = out m
        got = 1
      }
      if (!got) return 0
      # A msgid is a lookup key, so the two trees must spell it the same way.
      # C writes an embedded quote as \" and Ruby single-quoted source writes
      # it bare; they are one gettext key and must not compare as two.
      gsub(/\\"/, "\"", out)
      gsub("\\\\" Q, Q, out)
      LIT = out
      LITREST = s
      return 1
    }

    function is_comment(line) {
      if (LANG_KIND == "hash") return (line ~ /^[[:space:]]*#/)
      # Block-comment continuation needs the space: `* foo` is a comment,
      # `*title = g_strdup_printf (_("Process %d"), ...)` is a statement.
      return (line ~ /^[[:space:]]*(\/\/|--)/ || line ~ /^[[:space:]]*\*[[:space:]]/)
    }

    { line[NR] = $0 }

    END {
      for (i = 1; i <= NR; i++) {
        if (is_comment(line[i])) continue
        # A trailing backslash is a line continuation in both Ruby and C, and
        # it sits *between* the two halves of a msgid that was wrapped across
        # lines with one. It has to come off before the halves can be joined.
        # Left in, the census reports the first fragment as a message of its
        # own, which surfaces as one gap plus one extra for a string that is
        # perfectly fine.
        buf = line[i]
        sub(/\\[[:space:]]*$/, "", buf)
        own = length(buf)
        for (j = i + 1; j <= i + LOOKAHEAD && j <= NR; j++) {
          if (is_comment(line[j])) break
          nxt = line[j]
          sub(/\\[[:space:]]*$/, "", nxt)
          buf = buf " " nxt
        }

        pos = 1
        while (match(substr(buf, pos), /(^|[^A-Za-z0-9_.])(g_)?(_|N_|NC_|C_|n_|Nn_|np_|p_|s_|ngettext|gettext|dgettext|dngettext|dpgettext|dpgettext2|pgettext|npgettext)[[:space:]]*\(/)) {
          start = pos + RSTART - 1
          if (start > own) break          # this match belongs to a later line
          m = substr(buf, start, RLENGTH)
          sub(/^[^A-Za-z_]/, "", m); sub(/[[:space:]]*\($/, "", m)
          pos = start + RLENGTH
          rest = substr(buf, pos)

          # Domain-first forms: the first argument names the text domain and
          # is usually a macro, never the msgid. Drop it and read on.
          if (m ~ /^(g_)?d(n|p)?gettext2?$/) {
            if (rest !~ /,/) continue
            sub(/^[^,]*,/, "", rest)
          }
          sub(/^g_/, "", m)

          if (!take_lit(rest)) {
            expr = substr(rest, 1, 60)
            sub(/[[:space:]]*$/, "", expr)
            print "!unresolved\t" m "(" expr "\tunresolved\t" F ":" i
            continue
          }
          a = LIT; rest2 = LITREST
          ctxt = "-"; id = a; kind = "single"

          if (m == "C_" || m == "NC_" || m == "p_" || m == "np_" || m ~ /pgettext2?$/) {
            if (rest2 !~ /^[[:space:]]*,/) continue
            sub(/^[[:space:]]*,/, "", rest2)
            if (!take_lit(rest2)) continue
            ctxt = a; id = LIT
            if (m == "np_" || m == "npgettext") kind = "plural"
          } else if (m == "ngettext" || m == "n_" || m == "Nn_" || m == "dngettext") {
            kind = "plural"
          } else if (m == "s_" || m == "sgettext") {
            if (index(a, "|")) { ctxt = substr(a, 1, index(a, "|") - 1); id = substr(a, index(a, "|") + 1) }
          }
          if (id != "") print ctxt "\t" id "\t" kind "\t" F ":" i
        }
      }
    }' "$1"
}

for tree in "$@"; do
  TREE=${tree%/}
  sources "$TREE" | while IFS= read -r f; do
    rel=${f#"$TREE"/}
    case "$f" in

      # ---------------------------------------------------------------- .po
      # The po files are the only place the *shipped* message set is recorded,
      # and reading them needs no gettext tooling. msgid and msgctxt may be
      # split over continuation lines ("" then several "..." lines), so this
      # accumulates rather than matching one line.
      *.po|*.pot)
        awk -v F="$rel" '
          function flush(   k) {
            # Same canonical form as the marker scanner: an embedded quote is
            # a quote. po writes it \" and Ruby single-quoted source writes it
            # bare, and they are one key.
            gsub(/\\"/, "\"", id)
            gsub(/\\"/, "\"", ctxt)
            if (id != "" ) {
              print (ctxt == "" ? "-" : ctxt) "\t" id "\t" (plural ? "plural" : "po") "\t" F ":" line
            }
            id = ""; ctxt = ""; plural = 0; state = ""
          }
          function body(s) { sub(/^[^"]*"/, "", s); sub(/"[[:space:]]*$/, "", s); return s }
          /^msgctxt[[:space:]]/ { flush(); state = "c"; ctxt = body($0); line = NR; next }
          /^msgid[[:space:]]/   { if (state != "c") flush(); state = "i"; id = body($0); line = NR; next }
          /^msgid_plural[[:space:]]/ { plural = 1; state = "p"; next }
          /^msgstr/             { state = "s"; next }
          /^[[:space:]]*"/      { if (state == "c") ctxt = ctxt body($0); else if (state == "i") id = id body($0); next }
          /^[[:space:]]*$/      { flush(); next }
          { }
          END { flush() }
        ' "$f" ;;

      # ------------------------------------------------- GtkBuilder / XML-ish
      # translatable="yes" marks the *element text*, with the context in a
      # sibling context= or comments= attribute. Handled statefully because
      # GtkBuilder wraps long labels onto the next line.
      *.ui|*.ui.in)
        awk -v F="$rel" '
          {
            if (match($0, /translatable="(yes|true)"/)) {
              ctxt = "-"
              if (match($0, /context="[^"]*"/)) {
                ctxt = substr($0, RSTART + 9, RLENGTH - 10)
              }
              rest = $0; sub(/^.*translatable="(yes|true)"[^>]*>/, "", rest)
              if (rest ~ /</) { sub(/<.*$/, "", rest); if (rest != "") print ctxt "\t" rest "\tsingle\t" F ":" NR }
              else { open = 1; buf = rest; ln = NR; oc = ctxt }
              next
            }
            if (open) {
              buf = buf $0
              if (buf ~ /</) { sub(/<.*$/, "", buf); if (buf != "") print oc "\t" buf "\tsingle\t" F ":" ln; open = 0 }
            }
          }' "$f" ;;

      # metainfo / appstream / gschema: the whole point of the .in suffix is
      # that meson runs i18n.merge_file over it, so every <name>, <summary>,
      # <p>, <li>, <caption> and gschema <summary>/<description> is a message.
      *.xml|*.xml.in|*.xml.in.in)
        # Whole file as one string, then pull the text of each translatable
        # element - metainfo <name>/<summary>/<p>/<li>/<caption>/<keyword>
        # and gschema <summary>/<description>. <keyword> is easy to forget and
        # xgettext does extract it: Sudoku ships five. Read this way because those elements wrap
        # over several lines far more often than not, and a line-at-a-time
        # scan silently drops every paragraph longer than 80 columns.
        #
        # <release> notes are NOT extracted: the AppStream ITS rules xgettext
        # applies mark them untranslatable, and a scanner that takes them
        # reports hundreds of phantom messages for an app with a long history.
        # The opening tag may carry attributes - Sudoku writes
        # `<releases translate="no">` - so the pattern must not assume a bare
        # tag, or all 41 of its release notes come through.
        tr '\n' ' ' < "$f" \
        | sed -E 's|<releases( [^>]*)?>.*</releases>| |g; s|<release[ >][^<]*<\/release>| |g' \
        | grep -oE '<(name|summary|description|p|li|caption|keyword)( [^>]*)?>[^<]+</' \
        | grep -v 'translat[a-z]*="no"' \
        | sed -E 's|^<[a-z]+( [^>]*)?>||; s|</$||; s|[[:space:]]+| |g; s|^ ||; s| $||' \
        | while IFS= read -r m; do
            [ -n "$m" ] && printf -- '-\t%s\tsingle\t%s\n' "$m" "$rel"
          done ;;

      # .desktop.in - Name/GenericName/Comment/Keywords are the translated
      # keys. The old `_Name=` intltool spelling is still in some trees.
      # Keywords is one message, semicolons and all, and it carries a
      # translator comment telling translators not to touch them.
      *.desktop.in|*.desktop.in.in|*.desktop)
        grep -nE '^_?(Name|GenericName|Comment|Keywords|X-GNOME-FullName)=' "$f" 2>/dev/null \
        | while IFS=: read -r line rest; do
            printf -- '-\t%s\tsingle\t%s:%s\n' "${rest#*=}" "$rel" "$line"
          done ;;

      # ------------------------------------------------------------- markers
      # One awk over every code and blueprint file. The marker set is the union
      # of what Vala/C, blueprint, Python, GJS, Rust and the Ruby `gettext` gem
      # use, because a port and its original are being compared and both must
      # be read by the same rules.
      #
      #   _(  N_(  gettext(                     -> single
      #   C_(  NC_(  pgettext(  p_(  np_(       -> single, with context
      #   ngettext(  n_(  Nn_(                  -> plural, key is the singular
      #   dgettext(  g_dngettext(  dpgettext2(  -> domain first, then the rest
      #
      # `lang` tells the scanner what a comment looks like. It is not cosmetic:
      # `#` opens a comment in Ruby and Python and opens a *preprocessor
      # directive* in C, so treating it as a comment everywhere loses
      # `#define URI_FAILED_MESSAGE C_("toast-message", "Couldn't Open Link")`.
      *.rb|*.py) markers_awk "$f" "$rel" hash ;;
      *.vala|*.c|*.cpp|*.h|*.js|*.ts|*.rs|*.blp) markers_awk "$f" "$rel" slash ;;
    esac
  done
done | sort -u
:
