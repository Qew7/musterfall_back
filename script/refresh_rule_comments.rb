# frozen_string_literal: true
# encoding: utf-8

# Replace `# rule:` headers in battle rule files. Idempotent.

RULES_ROOT = File.expand_path("../app/domain/sim/battle/rules", __dir__)
RULE_LINE = /^\s*#\s*rule:.*\n/

ANNOTATIONS = {
  "anti_large/melee.rb" => "anti_large | melee | +35% melee damage vs cavalry and monster model classes.",
  "armor_piercing/melee.rb" => "armor_piercing | melee | Halves armor mitigation penalty on melee (50% of excess armor factor).",
  "armor_piercing/shooting.rb" => "armor_piercing | shooting | Same armor mitigation halving for ranged attacks.",
  "banner_aura/setup.rb" => "banner_aura | setup | Hero bannerAura on attach: +1 melee to host and first melee contributor.",
  "blast/shooting.rb" => "blast | shooting | Circular AoE shot: primary ×1, models in splash radius ×0.75.",
  "boar/melee.rb" => "boar_charge | melee | Flank/rear boarCharge marks ferocious allies in contact with target for +1 melee that round.",
  "breath/shooting.rb" => "breath | shooting | Teardrop template; auto-hits models under the shape.",
  "charge/melee.rb" => "charge | melee | After a charge (charged_distance > 0), melee ×1.3 unless unit has momentumCharge.",
  "common/shooting.rb" => "common | shooting | Default single-target ranged attack with hit roll and front-rank targeting.",
  "corpse_trail/movement.rb" => "corpse_trail | movement | Undead ignore movement penalty from corpseTrail terrain.",
  "corpse_trail/shooting.rb" => "corpse_trail | shooting | On hit, summons zombies within 6\" of the victim.",
  "disciplined/morale.rb" => "disciplined | morale | +1 morale break threshold.",
  "dodge/melee.rb" => "dodge | melee | Defender hit chance ×0.8 for melee.",
  "dodge/shooting.rb" => "dodge | shooting | Defender hit chance ×0.8 for ranged.",
  "fear/melee.rb" => "fear | melee | Attacker skips melee when fear_cannot_attack is set (failed charge fear check).",
  "fear/morale.rb" => "fear | morale | −1 break threshold when an enemy has fear and you are not fearless.",
  "fear/movement.rb" => "fear | movement | Charge fear checks between charger and defender; may halt charge or forbid defender attacks.",
  "ferocious/melee.rb" => "ferocious | melee | Consecutive kills on same target in contact ramp melee skill up to +6.",
  "flying/movement.rb" => "flying | movement | Flyer movement AI: leap, rear/flank charge priority, ignores ground obstacles.",
  "forestborn/movement.rb" => "forestborn | movement | Ranged forestborn repositions toward forest when cover needed to shoot.",
  "forestborn/shooting.rb" => "forestborn | shooting | +1 shooting skill when target is in forest.",
  "forestkin/melee.rb" => "forestkin | melee | Melee hit on target outside forest spawns forest terrain under target.",
  "forestkin/round.rb" => "forestkin | round | Heal +1 HP per round while wounded and standing in forest.",
  "ground/movement.rb" => "ground | movement | Default infantry movement AI: charge, flank/rear setup, contact waves, pathfinding.",
  "line/shooting.rb" => "line | shooting | Line-shaped shooting template (beam/artillery line).",
  "machine/shooting.rb" => "machine | shooting | Machine ranged damage ×1.25.",
  "magic_effects.rb" => "magic_effects | shared | Applies spell-effect trigger damage and logs magic actions.",
  "magic_effects/melee.rb" => "magic_effects | melee | after_melee_hit spell effects damage the attacker.",
  "magic_effects/movement.rb" => "magic_effects | movement | ranged_hindered halves move; after_move effects damage movers.",
  "magic_effects/shooting.rb" => "magic_effects | shooting | ranged_hidden blocks targeting; ranged_hindered ×0.5 hit; magic_ward halves magic damage.",
  "magic_effects/turn.rb" => "magic_effects | turn | start_turn/end_turn spell triggers deal damage.",
  "march/movement.rb" => "march | movement | Ground units (not flying/machine/undead) get march move when no enemy in clearance.",
  "momentum_charge/melee.rb" => "momentum_charge | melee | Charge bonus scales with charged_distance (up to +50% damage); resets after attack.",
  "muster/morale.rb" => "muster | morale | Hero muster raises ally effective morale to hero morale within range.",
  "outrider/movement.rb" => "outrider | movement | Never melee-moves; kites to ideal shooting range.",
  "poison/melee.rb" => "poison | melee | After hit, kills one model if strike did not already kill a model (not vs undead).",
  "regen/round.rb" => "regen | round | d6 3+ heals +2 HP each round while wounded.",
  "resolute/morale.rb" => "resolute | morale | +2 break threshold when combat score is positive.",
  "resolute_aura/setup.rb" => "resolute_aura | setup | Attached hero grants host resolute in ability set.",
  "rune_armor/melee.rb" => "rune_armor | melee | Non-magic damage ×⅔.",
  "rune_armor/shooting.rb" => "rune_armor | shooting | Non-magic ranged damage ×⅔.",
  "shieldwall/melee.rb" => "shieldwall | melee | Incoming frontal charge damage ×0.75 (front vector, charged_distance > 0).",
  "skirmisher/melee.rb" => "skirmisher | melee | No flank/rear damage bonus; may shoot without requiring front arc.",
  "sling_catapult/shooting.rb" => "sling_catapult | shooting | Consumes nearest slingFodder goblin within 6\" to fire a blast shot.",
  "support_rank/melee.rb" => "support_rank | melee | Second rank doubles front-contact attacking models (capped by models_remaining).",
  "throw_rocks/movement.rb" => "throw_rocks | movement | Non-melee mover advances when no line of sight for ranged throw.",
  "toxin.rb" => "toxin | shared | First hit permanently −1 skill and −1 melee on target (and primary contributor).",
  "toxin/melee.rb" => "toxin | melee | Applies toxin debuff after melee hit.",
  "toxin/shooting.rb" => "toxin | shooting | Applies toxin debuff after ranged hit.",
  "undead/morale.rb" => "undead | morale | Morale failure destroys unit HP or chips hero instead of routing.",
  "undead/round.rb" => "undead | round | Faction passive: one wounded undead unit heals +1 HP per round.",
  "volley/shooting.rb" => "volley | shooting | Up to two targets: primary ×1, secondary ×0.65.",
  "wildborn/morale.rb" => "wildborn | morale | Counts as fearless while in forest (used by fear morale).",
  "wildborn/movement.rb" => "wildborn | movement | Fearless in forest; may charge through terrain toward forest targets.",
  "wizard/movement.rb" => "wizard | movement | Casters path toward spell anchor when no valid cast is available."
}.freeze

ANNOTATIONS.each do |rel, body|
  path = File.join(RULES_ROOT, rel)
  abort "missing #{rel}" unless File.exist?(path)

  lines = File.readlines(path, encoding: "UTF-8")
  lines.reject! { |line| line.match?(RULE_LINE) }

  idx = lines.index { |line| line.strip == "module_function" }
  abort "no module_function in #{rel}" unless idx

  indent = lines[idx][/\A(\s*)/, 1]
  lines.insert(idx, "#{indent}# rule: #{body}\n")
  File.write(path, lines.join)
  puts "updated #{rel}"
end

puts "done: #{ANNOTATIONS.size} files"
