#!/usr/bin/env ruby
# frozen_string_literal: true

# Turn a source tree into a message catalogue document, and two catalogue
# documents into a parity document.
#
#   catalogue.rb <tree> --role upstream           > upstream-catalogue.yaml
#   catalogue.rb <tree> --role port               > port-catalogue.yaml
#   catalogue.rb --compare upstream.yaml port.yaml > translation-parity.yaml
#
# Both documents are **generated and never hand-edited**. Regenerate them and
# the numbers move; anything a person wrote in them would be lost, which is
# why the prose — why a gap is open, which component it waits on, what a
# reviewer concluded — lives in TRANSLATION_PARITY.md and not here. The YAML
# holds facts that a machine can recompute; the markdown holds judgements that
# it cannot.
#
# The catalogue is sorted by (msgctxt, msgid), so `diff` over two of them is
# readable even without the compare step.

require 'yaml'
require 'json'
require 'date'

CENSUS = File.join(__dir__, 'msgid-census.sh')

# --------------------------------------------------------------------------
# Reading a tree

# One census row per call site; the catalogue groups them by key. `uses` is
# the number of call sites and is deliberately kept out of the identity - two
# trees that reach the same key a different number of times still hold the
# same message. See SKILL.md, Step 2, metric 2.
def messages_in(tree)
  rows = `#{CENSUS.shellescape} #{tree.shellescape}`.lines(chomp: true)
  raise "census failed for #{tree}" unless $CHILD_STATUS.success?

  grouped = Hash.new { |h, k| h[k] = { kinds: [], sites: [] } }
  unresolved = []
  rows.each do |row|
    ctxt, id, kind, site = row.split("\t", 4)
    next if id.nil? || id.empty?
    # A marker whose argument is an expression rather than a literal. Not a
    # message - it is a place where a message is, that the scanner cannot
    # read. Carried out separately so it is counted and chased, never merged
    # into the catalogue and never silently dropped.
    if ctxt == '!unresolved'
      unresolved << { 'marker' => id, 'site' => site }
      next
    end
    # po/ is scanned by the census on purpose - Step 1 diffs it against the
    # source to prove the scanner - but it is not part of the catalogue. A
    # .po holds every msgid the last msgmerge knew about, including the ones
    # upstream has since deleted, so counting it here would report a tree as
    # having messages its code no longer emits.
    next if site.to_s.start_with?('po/') || site.to_s.match?(/\.pot?:/)

    key = [ctxt == '-' ? nil : ctxt, id]
    grouped[key][:kinds] << kind
    grouped[key][:sites] << site
  end

  @unresolved = unresolved.sort_by { |u| u['site'].to_s }
  grouped.sort_by { |(ctxt, id), _| [ctxt.to_s, id] }.map do |(ctxt, id), v|
    entry = {}
    entry['ctxt'] = ctxt if ctxt
    entry['id'] = id
    # A key marked both ways in one tree is a defect in that tree, not a
    # comparison failure, so it is recorded rather than resolved: `plural`
    # wins for the kind and both spellings are listed.
    entry['kind'] = v[:kinds].include?('plural') ? 'plural' : v[:kinds].uniq.first
    entry['kinds'] = v[:kinds].uniq.sort if v[:kinds].uniq.size > 1
    entry['uses'] = v[:sites].size
    entry['sites'] = v[:sites].sort
    entry
  end
end

# Count the messages in one .po as `msgfmt --statistics` would: translated,
# fuzzy, untranslated.
#
# Entry-at-a-time rather than line-at-a-time, because four things make a line
# scan wrong and each of them moves the number by hundreds:
#
#   - a long msgstr is written as `msgstr ""` plus continuation lines, so the
#     first line of a translated entry looks exactly like an empty one;
#   - `#~` marks an obsolete entry, kept in the file for reference and left
#     out of the .mo. gnome-contacts has 14 fuzzy flags on obsolete entries
#     against 6 on live ones, so counting them roughly triples the figure;
#   - the file header is an entry whose msgid is empty - it holds Plural-Forms
#     and the translator's name, not a translation;
#   - `#, fuzzy` marks a translation msgmerge guessed from a similar msgid.
#     msgfmt leaves it out of the .mo, so the user sees English however full
#     the msgstr looks. It is neither translated nor untranslated: it is the
#     one category a translator can clear without writing anything new.
#
# A plural message counts once, not once per form, and is translated only when
# every form is filled.
def po_counts(path)
  translated = untranslated = fuzzy = 0

  # CRLF is normalised first. It is not hypothetical: gnome-contacts' th.po
  # has CRLF terminators and every other .po has LF, so a blank-line split on
  # the raw bytes finds one giant entry there and reports Thai as having no
  # messages at all - silently, because the file parses fine everywhere else.
  File.read(path).gsub("\r\n", "\n").split(/\n[ \t]*\n/).each do |entry|
    lines = entry.lines.map(&:chomp)
    next if lines.any? { |l| l.start_with?('#~') }        # obsolete
    next unless lines.any? { |l| l.start_with?('msgstr') }

    # The header is the entry whose msgid is empty. Accumulate msgid and its
    # continuation lines and stop at msgstr - a continuation line looks the
    # same whichever field it belongs to, and letting msgstr's lines land in
    # msgid makes every header look like a real message.
    msgid = []
    in_msgid = false
    lines.each do |l|
      if l.start_with?('msgid ')
        in_msgid = true
        msgid << l.sub(/^msgid\s*/, '')
      elsif in_msgid && l.strip.start_with?('"')
        msgid << l.strip
      elsif in_msgid
        break
      end
    end
    next if msgid.empty? || msgid.all? { |m| m.strip == '""' }   # header

    if lines.any? { |l| l.start_with?('#,') && l.include?('fuzzy') }
      fuzzy += 1
      next
    end

    # Walk the msgstr blocks; a form is filled if any of its lines carries
    # something between the quotes.
    filled = []
    in_msgstr = false
    lines.each do |l|
      if l.start_with?('msgstr')
        filled << (l.sub(/^msgstr(\[\d+\])?\s*/, '').strip != '""')
        in_msgstr = true
      elsif in_msgstr && l.strip.start_with?('"')
        filled[-1] ||= (l.strip != '""')
      else
        in_msgstr = false
      end
    end
    filled.all? ? translated += 1 : untranslated += 1
  end

  [translated, untranslated, fuzzy]
end

# The language set is counted from the .po files rather than from LINGUAS,
# and the two are compared - a language in one and not the other is a defect
# that is invisible if you only ever read one of them.
def languages_in(tree)
  po_dir = File.join(tree, 'po')
  return { 'count' => 0, 'list' => [], 'translated_strings' => 0 } unless Dir.exist?(po_dir)

  files = Dir.glob(File.join(po_dir, '*.po')).map { |f| File.basename(f, '.po') }.sort
  linguas_path = File.join(po_dir, 'LINGUAS')
  # LINGUAS is whitespace-separated language codes with `#` comment *lines*.
  # Rejecting tokens that start with '#' is not enough: a comment's remaining
  # words ("Please", "keep", "this"...) survive and are reported as languages
  # the file has and the directory lacks, which buries any real finding.
  linguas = if File.exist?(linguas_path)
              File.readlines(linguas_path).map { |l| l.sub(/#.*/, '') }.join(' ').split.sort
            end

  translated = untranslated = fuzzy = 0
  Dir.glob(File.join(po_dir, '*.po')).each do |f|
    t, u, z = po_counts(f)
    translated += t
    untranslated += u
    fuzzy += z
  end

  out = { 'count' => files.size, 'translated_strings' => translated,
          'untranslated_strings' => untranslated, 'fuzzy_strings' => fuzzy,
          'list' => files }
  unless linguas.nil?
    out['linguas_matches_files'] = (linguas == files)
    out['only_in_linguas'] = linguas - files unless (linguas - files).empty?
    out['only_in_po_files'] = files - linguas unless (files - linguas).empty?
  end
  out
end

# The domain is the .mo filename, so it must be upstream's for upstream's
# catalogues to be found. Read rather than assumed, in the order the answer is
# most likely to be right, and report where it came from - a wrong domain
# orphans every catalogue the port inherited, and it is the single easiest
# field to get quietly wrong.
#
# kgx is the case that defeats a one-line heuristic: `project('gnome-console')`
# but `i18n.gettext(bin_name)` with `bin_name = 'kgx'`, and the .mo files are
# `kgx.mo`. Guessing the project name renames the domain and strands 61
# languages.
def domain_in(tree)
  po_meson = File.join(tree, 'po', 'meson.build')
  if File.exist?(po_meson) && (m = File.read(po_meson).match(/i18n\.gettext\s*\(\s*([^,)\s]+)/m))
    arg = m[1]
    return [arg[1..-2], 'po/meson.build'] if arg =~ /\A['"].*['"]\z/
    return [project_name(tree), 'meson.project_name()'] if arg.include?('project_name')

    resolved, alts = resolve_meson_var(tree, arg)
    return [resolved, "po/meson.build (#{arg}#{alts.empty? ? '' : ", also #{alts.join(', ')}"})"] if resolved
  end

  meson = File.join(tree, 'meson.build')
  if File.exist?(meson) && (m = File.read(meson).match(/GETTEXT_PACKAGE['"]?\s*,\s*['"]([^'"]+)['"]/))
    return [m[1], 'GETTEXT_PACKAGE']
  end

  # A committed .pot is named for the domain.
  pot = Dir.glob(File.join(tree, 'po', '*.pot')).first
  return [File.basename(pot, '.pot'), 'po/*.pot'] if pot

  Dir.glob(File.join(tree, '{Rakefile,lib/**/*.rb,bin/*}')).each do |f|
    next unless File.file?(f)

    src = File.read(f)
    if (m = src.match(/(?:\.domain\s*=|TEXT_?DOMAIN\s*=|bindtextdomain[\s(]+)\s*["']([^"']+)["']/))
      return [m[1], f.sub("#{tree}/", '')]
    end
  end

  pn = project_name(tree)
  pn ? [pn, 'meson project() - unconfirmed'] : [nil, nil]
rescue StandardError
  [nil, nil]
end

def project_name(tree)
  meson = File.join(tree, 'meson.build')
  File.exist?(meson) ? File.read(meson)[/project\s*\(\s*'([^']+)'/, 1] : nil
end

# One level of meson variable resolution, no more. Conditional assignments are
# not evaluated: the last one wins and the others are reported alongside, so a
# wrong pick is visible instead of silent.
def resolve_meson_var(tree, name)
  values = Dir.glob(File.join(tree, '{meson.build,*/meson.build}')).flat_map do |f|
    File.read(f).scan(/^\s*#{Regexp.escape(name)}\s*=\s*['"]([^'"]+)['"]/).flatten
  end
  return [nil, []] if values.empty?

  [values.last, values[0..-2].uniq]
end

def git(tree, *args)
  out = `git -C #{tree.shellescape} #{args.join(' ')} 2>/dev/null`.strip
  out.empty? ? nil : out
end

def catalogue(tree, role, domain_override)
  msgs = messages_in(tree)
  langs = languages_in(tree)
  domain = domain_in(tree)

  {
    'version' => 1,
    'tree' => {
      'role' => role,
      'path' => tree,
      'ref' => git(tree, 'rev-parse', '--abbrev-ref', 'HEAD'),
      'sha' => git(tree, 'rev-parse', '--short', 'HEAD'),
      'scanned' => Date.today.to_s
    }.compact,
    'domain' => domain_override || domain[0],
    'domain_source' => domain_override ? 'passed with --domain' : domain[1],
    'totals' => {
      'messages' => msgs.size,
      'occurrences' => msgs.sum { |m| m['uses'] },
      'reused' => msgs.count { |m| m['uses'] > 1 },
      'plural' => msgs.count { |m| m['kind'] == 'plural' },
      'with_context' => msgs.count { |m| m['ctxt'] },
      # Non-zero means the catalogue below is incomplete by at least this
      # many messages. Census them by hand before writing any ledger.
      'unresolved' => @unresolved.size
    },
    'languages' => langs,
    'unresolved' => @unresolved,
    'messages' => msgs
  }
end

# --------------------------------------------------------------------------
# Comparing two catalogues

def key_of(m) = [m['ctxt'], m['id']]

def compare(up, port)
  up_by = up['messages'].to_h { |m| [key_of(m), m] }
  port_by = port['messages'].to_h { |m| [key_of(m), m] }

  rows = (up_by.keys | port_by.keys).sort_by { |ctxt, id| [ctxt.to_s, id] }.map do |key|
    u = up_by[key]
    p = port_by[key]
    row = {}
    row['ctxt'] = key[0] if key[0]
    row['id'] = key[1]
    row['state'] = if u.nil?  then 'extra'
                   elsif p.nil? then 'gap'
                   else 'ported'
                   end
    row['kind'] = { 'upstream' => u&.dig('kind'), 'port' => p&.dig('kind') }
    row['uses'] = { 'upstream' => u&.dig('uses') || 0, 'port' => p&.dig('uses') || 0 }

    # Two flags, and neither of them changes `state`. A key present in both
    # trees has translation parity by definition; these say the port reaches
    # it wrongly or in the wrong number of places, which is a component
    # question. SKILL.md, Step 2, metric 2.
    row['kind_mismatch'] = true if u && p && u['kind'] != p['kind']
    row['uses_mismatch'] = true if u && p && u['uses'] != p['uses']

    row['upstream_sites'] = u['sites'] if u
    row['port_sites'] = p['sites'] if p
    # The byte-identical English the port owes, carried so that closing a gap
    # is transcription and never authorship.
    row['text_owed'] = key[1] if row['state'] == 'gap'
    row
  end

  up_langs = up.dig('languages', 'list') || []
  port_langs = port.dig('languages', 'list') || []

  {
    'version' => 1,
    'upstream' => up['tree'].merge('domain' => up['domain']).merge(up['totals']),
    'port' => port['tree'].merge('domain' => port['domain']).merge(port['totals']),
    'summary' => {
      'ported' => rows.count { |r| r['state'] == 'ported' },
      'gaps' => rows.count { |r| r['state'] == 'gap' },
      'extra' => rows.count { |r| r['state'] == 'extra' },
      'kind_mismatch' => rows.count { |r| r['kind_mismatch'] },
      'uses_mismatch' => rows.count { |r| r['uses_mismatch'] },
      'occurrences' => { 'upstream' => up['totals']['occurrences'], 'port' => port['totals']['occurrences'] },
      'languages' => { 'upstream' => up_langs.size, 'port' => port_langs.size },
      'languages_missing' => up_langs - port_langs,
      'domain_matches' => up['domain'] == port['domain'],
      # The one line a reader looks at. Every other field explains it.
      'parity' => (rows.none? { |r| r['state'] == 'gap' } &&
                   rows.none? { |r| r['kind_mismatch'] } &&
                   (up_langs - port_langs).empty? &&
                   up['domain'] == port['domain'])
    },
    'messages' => rows
  }
end

# --------------------------------------------------------------------------

require 'shellwords'
require 'English'

args = ARGV.dup
if args.first == '--compare'
  a, b = args[1], args[2]
  abort 'usage: catalogue.rb --compare <upstream.yaml> <port.yaml>' unless a && b
  puts compare(YAML.safe_load_file(a), YAML.safe_load_file(b)).to_yaml
else
  tree = args.shift
  abort 'usage: catalogue.rb <tree> [--role upstream|port] [--domain NAME]' unless tree

  role = 'upstream'
  domain = nil
  until args.empty?
    case args.shift
    when '--role' then role = args.shift
    when '--domain' then domain = args.shift
    end
  end
  puts catalogue(tree, role, domain).to_yaml
end
