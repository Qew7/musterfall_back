# frozen_string_literal: true
# encoding: utf-8

# Rule policy belongs in rules/<rule>/<phase>.rb. This scan is the lock:
# leftover pre-commit runs it, so agents cannot "finish" with inlined branches.
module RuleLayerLint
  ROOT = File.expand_path("../..", __dir__)

  Hit = Struct.new(:file, :line, :message, keyword_init: true)

  LAYERS = [
    {
      glob: "app/domain/sim/battle/phases/**/*.rb",
      bans: [
        [ /abilities\.include\?/, "ability branch in phase — rules/<rule>/<phase>.rb" ],
        [ /SpellEffects\.status\?/, "spell-effect branch in phase — rules/<rule>/<phase>.rb" ],
        [ /\bflying\?/, "flying? in phase — Flying::Movement owns the wave" ],
        [ /contact_wave\?/, "contact_wave? in phase — Ground.plan_waves owns the list" ],
        [ /orbit_mode\?/, "orbit_mode? in phase — Ground owns wrap/orbit" ],
        [ /:flyer_setup_rear|:flyer_setup_flank|:flyer_approach|:flyer_charge|"flyer_charge"|"flyer_leap"/,
          "flyer mode/kind in phase — set it on the Flying plan" ]
      ]
    },
    {
      glob: "app/domain/sim/battle/decisions/**/*.rb",
      bans: [
        [ /:flyer_setup_rear|:flyer_setup_flank|:flyer_approach|:flyer_charge/,
          "flyer modes in facade — Flying::Movement" ],
        [ /def contact_wave\?/, "contact_wave? facade — Ground.contact_wave?" ],
        [ /def orbit_mode\?/, "orbit_mode? facade — Ground.orbit_mode?" ],
        [ /SpellEffects\.status\?/, "spell-effect branch in facade — rules/<rule>/<phase>.rb" ]
      ]
    },
    {
      glob: "app/domain/sim/battle/pathing/**/*.rb",
      bans: [
        [ /:orbit_flank|:wrap_rear|:flyer_setup_rear|:flyer_setup_flank|:flyer_approach|:flyer_charge/,
          "maneuver policy in pathing — Ground/Flying approach_goal_point" ],
        [ /contact_wave\?/, "contact_wave? in pathing" ],
        [ /abilities\.include\?/, "ability branch in pathing" ],
        [ /SpellEffects\.status\?/, "spell-effect branch in pathing — rules/<rule>/<phase>.rb" ]
      ]
    },
    {
      glob: "app/domain/sim/geometry/**/*.rb",
      bans: [
        [ /abilities\.include\?/, "ability branch in geometry — rules/ own policy" ],
        [ /SpellEffects\.status\?/, "spell-effect branch in geometry — rules/ own policy" ]
      ]
    }
  ].freeze

  module_function

  def scan(root: ROOT)
    hits = []
    LAYERS.each do |layer|
      Dir.glob(File.join(root, layer[:glob])).sort.each do |path|
        File.readlines(path, chomp: true, encoding: "UTF-8").each_with_index do |text, index|
          next if text.match?(/^\s*#/)

          layer[:bans].each do |regex, message|
            next unless text.match?(regex)

            hits << Hit.new(file: rel(root, path), line: index + 1, message: message)
          end
        end
      end
    end
    hits
  end

  def report(hits)
    hits.map { |hit| "#{hit.file}:#{hit.line}: #{hit.message}" }
  end

  def rel(root, path)
    path.delete_prefix("#{File.expand_path(root)}/")
  end
end

if $PROGRAM_NAME == __FILE__
  hits = RuleLayerLint.scan
  if hits.empty?
    warn "rule-layer lint: clean"
    exit 0
  end

  warn "rule-layer lint: policy leaked out of rules/"
  warn RuleLayerLint.report(hits).join("\n")
  exit 1
end
