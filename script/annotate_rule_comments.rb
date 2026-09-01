# frozen_string_literal: true
# encoding: utf-8

# One-shot: inject `# rule:` headers into battle rule files. Safe to re-run (skips if present).

RULES_ROOT = File.expand_path("../app/domain/sim/battle/rules", __dir__)
RULE_LINE = /^\s*#\s*rule:/

ANNOTATIONS = {
  "anti_large/melee.rb" =>
    "anti_large | melee | +35% melee damage vs cavalry and monster targets. Balance: spikes vs elite cavalry/rare bruisers.",
  "armor_piercing/melee.rb" =>
    "armor_piercing | melee | Halves the armor mitigation penalty (50% of excess armor factor). Balance: helps vs medium/heavy in melee contact.",
  "armor_piercing/shooting.rb" =>
    "armor_piercing | shooting | Same armor mitigation halving for ranged attacks. Balance: key for handgunners and outriders in standoff.",
  "banner_aura/setup.rb" =>
    "banner_aura | setup | Attached hero with bannerAura grants host and first melee contributor +1 melee. Balance: army setup buff, not in 1v1 duels without hero.",
  "blast/shooting.rb" =>
    "blast | shooting | Circular AoE template: primary ×1, splash in radius ×0.75. Balance: artillery and sling catapult AoE.",
  "boar/melee.rb" =>
    "boar_charge | melee | Flank/rear boarCharge flags ferocious allies in contact for +1 melee that round. Balance: synergy combo, not solo 1v1.",
  "breath/shooting.rb" =>
    "breath | shooting | Teardrop template, auto-hits models under shape. Balance: dragon breath; strong ranged opener.",
  "charge/melee.rb" =>
    "charge | melee | Post-charge melee damage ×1.3 unless unit has momentumCharge. Balance: core charge payoff in contact duels.",
  "common/shooting.rb" =>
    "common | shooting | Default single-target ranged shot with hit roll and front-rank focus. Balance: baseline for line archers in deploy=ranged.",
  "corpse_trail/movement.rb" =>
    "corpse_trail | movement | Undead ignore corpseTrail terrain movement penalty. Balance: terrain only; no effect in empty duels.",
  "corpse_trail/shooting.rb" =>
    "corpse_trail | shooting | On hit, summons zombies near the victim. Balance: snowball after kills; weak in short duels.",
  "disciplined/morale.rb" =>
    "disciplined | morale | +1 morale break threshold. Balance: stabilizes empire line vs fear and combat losses.",
  "dodge/melee.rb" =>
    "dodge | melee | Defender hit chance ×0.8. Balance: EHP boost for war_dancers in melee.",
  "dodge/shooting.rb" =>
    "dodge | shooting | Same hit chance ×0.8 vs ranged. Balance: helps skirmishers survive standoff volleys.",
  "fear/melee.rb" =>
    "fear | melee | Blocks melee if defender passed charge fear check (fear_cannot_attack). Balance: can shut down a charge turn.",
  "fear/morale.rb" =>
    "fear | morale | −1 break threshold when enemy has fear and you lack fearless. Balance: undead pressure in mixed fights.",
  "fear/movement.rb" =>
    "fear | movement | Charge fear checks: non-fear vs fear may halt charge; fear vs non-fear may forbid defender attacks. Balance: charge interaction before contact.",
  "ferocious/melee.rb" =>
    "ferocious | melee | Kill streak on same target ramps melee skill up to +6. Balance: orc sustain DPS in long melee trades.",
  "flying/movement.rb" =>
    "flying | movement | Flyer AI: leap pathing, rear/flank charge priority, ignores ground obstacles. Balance: closes standoff fast; strong in rare duels.",
  "forestborn/movement.rb" =>
    "forestborn | movement | Ranged forestborn seeks forest when shooting needs cover. Balance: terrain-dependent; flat duels ignore.",
  "forestborn/shooting.rb" =>
    "forestborn | shooting | +1 shooting skill when target stands in forest. Balance: wildwood shootouts with terrain.",
  "forestkin/melee.rb" =>
    "forestkin | melee | Melee hit outside forest spawns forest terrain under target. Balance: mid-fight terrain shift.",
  "forestkin/round.rb" =>
    "forestkin | round | In forest, heal +1 HP per round while wounded. Balance: treeman/dryad sustain over long fights.",
  "ground/movement.rb" =>
    "ground | movement | Default infantry AI: charge, flank/rear setup, contact waves, pathfinding. Balance: drives melee deploy and post-standoff closes.",
  "line/shooting.rb" =>
    "line | shooting | Line template artillery/magic beam. Balance: inferno cannon and similar rare artillery.",
  "machine/shooting.rb" =>
    "machine | shooting | Ranged damage ×1.25 for siege machines. Balance: boosts cannons and catapults in standoff.",
  "magic_effects.rb" =>
    "magic_effects | shared | Applies spell-effect damage and logs magic trigger actions. Balance: spell DoT and proc damage.",
  "magic_effects/melee.rb" =>
    "magic_effects | melee | after_melee_hit effects damage the attacker. Balance: thorns-style retaliation.",
  "magic_effects/movement.rb" =>
    "magic_effects | movement | ranged_hindered halves move; after_move effects damage units that moved. Balance: movement debuff spells.",
  "magic_effects/shooting.rb" =>
    "magic_effects | shooting | ranged_hidden blocks targeting; ranged_hindered ×0.5 hit; magic_ward halves magic damage. Balance: defensive spell layers.",
  "magic_effects/turn.rb" =>
    "magic_effects | turn | start_turn/end_turn spell triggers deal damage. Balance: sustained magic attrition.",
  "march/movement.rb" =>
    "march | movement | Extra march move when no enemy in clearance (ground, not undead/machine/flying). Balance: tempo before contact.",
  "momentum_charge/melee.rb" =>
    "momentum_charge | melee | Charge bonus scales with distance (up to +50% damage); resets after attack. Balance: cavalry/flyer charge scaling in duels.",
  "muster/morale.rb" =>
    "muster | morale | Hero muster aura raises ally effective morale to hero morale in range. Balance: army morale anchor, not 1v1.",
  "outrider/movement.rb" =>
    "outrider | movement | Never melee-moves; kites to ideal shooting range. Balance: outriders stay at range in duels.",
  "poison/melee.rb" =>
    "poison | melee | After hit, kills one extra model if strike did not already kill. Balance: attrition vs infantry; strong in long 1v1.",
  "regen/round.rb" =>
    "regen | round | d6 3+ heals +2 HP each round while wounded. Balance: stone_trolls and troll heroes sustain.",
  "resolute/morale.rb" =>
    "resolute | morale | +2 break threshold when combat score is positive. Balance: skeleton_block holds while winning trades.",
  "resolute_aura/setup.rb" =>
    "resolute_aura | setup | Attached hero grants host resolute ability. Balance: setup-only army buff.",
  "rune_armor/melee.rb" =>
    "rune_armor | melee | Non-magic damage ×⅔. Balance: rift_heavies tank physical melee and shooting.",
  "rune_armor/shooting.rb" =>
    "rune_armor | shooting | Same ×⅔ vs non-magic ranged. Balance: counters armor_piercing partially.",
  "shieldwall/melee.rb" =>
    "shieldwall | melee | Incoming frontal charge damage ×0.75. Balance: no standoff effect; matters after charge/contact only.",
  "skirmisher/melee.rb" =>
    "skirmisher | melee | Ignores flank/rear damage bonus; can shoot without front arc. Balance: war_dancers/goblins avoid facing punish.",
  "sling_catapult/shooting.rb" =>
    "sling_catapult | shooting | Consumes nearest slingFodder goblin for blast shot. Balance: glass cannon AoE needing fodder.",
  "support_rank/melee.rb" =>
    "support_rank | melee | Second rank doubles attacking models on front contact (capped). Balance: halberdiers spike in formed melee.",
  "throw_rocks/movement.rb" =>
    "throw_rocks | movement | Non-melee mover closes when no LoS for ranged throw. Balance: treeman approaches before rocks.",
  "toxin.rb" =>
    "toxin | shared | First hit permanently −1 skill and −1 melee on target. Balance: stacking debuff over long fights.",
  "toxin/melee.rb" =>
    "toxin | melee | Applies shared toxin debuff after melee hit. Balance: melee poison attrition.",
  "toxin/shooting.rb" =>
    "toxin | shooting | Applies shared toxin debuff after ranged hit. Balance: ranged poison attrition.",
  "undead/morale.rb" =>
    "undead | morale | Failed break destroys unit HP or chips hero HP instead of routing. Balance: all-or-nothing undead blocks.",
  "undead/round.rb" =>
    "undead | round | Faction passive: one wounded undead unit heals +1 HP/round. Balance: slow undead recovery in long fights.",
  "volley/shooting.rb" =>
    "volley | shooting | Up to two targets: primary ×1, secondary ×0.65. Balance: limited multi-target ranged.",
  "wildborn/morale.rb" =>
    "wildborn | morale | Counts as fearless while in forest (feeds fear morale). Balance: wildwood vs fear in terrain.",
  "wildborn/movement.rb" =>
    "wildborn | movement | Fearless in forest; can charge through terrain to forest targets. Balance: forest-only mobility edge.",
  "wizard/movement.rb" =>
    "wizard | movement | Casters path toward spell anchor when no valid cast. Balance: hero/caster positioning, not line 1v1."
}.freeze

ANNOTATIONS.each do |rel, body|
  path = File.join(RULES_ROOT, rel)
  abort "missing #{rel}" unless File.exist?(path)

  lines = File.readlines(path)
  next if lines.any? { |line| line.match?(RULE_LINE) }

  idx = lines.index { |line| line.strip == "module_function" }
  abort "no module_function in #{rel}" unless idx

  indent = lines[idx][/\A(\s*)/, 1]
  lines.insert(idx, "#{indent}# rule: #{body}\n")
  File.write(path, lines.join)
  puts "annotated #{rel}"
end

puts "done: #{ANNOTATIONS.size} files"
