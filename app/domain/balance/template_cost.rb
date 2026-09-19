module Balance
  # Deterministic estimate for seed profiles, not a live win-rate adjustment.
  # See docs/template_cost.md for calibration data and limitations.
  module TemplateCost
    module_function

    def compute(attributes, reference_profiles:)
      raise ArgumentError, "reference_profiles must not be empty" if reference_profiles.empty?
      rules = Array(attributes[:abilities]).uniq
      models = attributes.fetch(:models).to_f
      health = models * attributes.fetch(:model_health)
      files = [ attributes.fetch(:width), models ].min
      fighters = rules.include?("supportRank") ? [ files * 2, models ].min : files
      skill = attributes.fetch(:skill)
      # Melee SK is a comparison (3/6, 4/6, 5/6), not a linear multiplier.
      hit = reference_profiles.sum { |enemy| (skill <=> enemy.fetch(:skill)) + 4 } / (6.0 * reference_profiles.size)
      hit = [ hit + 0.08, 5 / 6.0 ].min if rules.include?("ferocious")
      melee = fighters * attributes.fetch(:attacks) * effective_power(attributes, "melee", reference_profiles: reference_profiles) * hit
      melee *= 1 + (attributes.fetch(:initiative) - 3) * 0.025
      melee *= 1.03 if rules.include?("boarCharge")
      melee += fighters * hit * 0.65 if rules.include?("poison") && melee.positive?
      # Extra round attack uses every model, independent of the attacks stat.
      melee += models * (attributes.fetch(:melee) / 2.2).round * hit if rules.include?("lavaSpit")

      shooting = shooting_power(attributes, rules, files, reference_profiles: reference_profiles)
      magic = rules.include?("wizard") ? effective_power(attributes, "magic", reference_profiles: reference_profiles) * 1.8 : 0.0
      mobility = 1 + ([ attributes.fetch(:movement), 10 ].min - 3) * 0.025
      mobility += 0.30 if rules.include?("flying")
      melee *= 0.45 if rules.intersect?(%w[outrider throwRocks])
      offense = melee * mobility + shooting + magic
      offense *= 1.12 if rules.include?("toxin") && offense.positive?

      # Apply defensive effects before rounding, just as combat does.
      incoming = incoming_factor(attributes, reference_profiles: reference_profiles)
      incoming *= 0.8 if rules.include?("dodge")
      incoming *= reference_profiles.sum { |enemy| (enemy.fetch(:skill) <=> skill) + 4 } / (4.0 * reference_profiles.size)
      health += 2 if rules.include?("regen")
      health += 2 if rules.include?("forestkin")
      morale = attributes.fetch(:morale) + (rules.include?("disciplined") ? 1 : 0)
      morale += 1 if rules.include?("resolute")
      staying = 1 + (morale - 5) * 0.045
      staying += 0.08 if rules.intersect?(%w[fear fearless])
      staying += 0.04 if rules.include?("wildborn") && !rules.intersect?(%w[fear fearless])
      # Undead trades routing for crumble and loses marching; no blanket surcharge.
      # Multi-wound models retain their attacks until an entire model dies.
      persistence = Math.sqrt(attributes.fetch(:model_health))
      durability = health / incoming * staying * persistence
      raw = 14 * Math.sqrt(durability * (1 + offense))
      raw += 15 * Math.sqrt(health) if rules.include?("flying")
      raw += 20 if rules.include?("fear")
      raw += 35 if rules.include?("corpseTrail") && (melee + shooting).positive?
      if attributes.fetch(:kind) == "hero"
        raw += 35 # attachment and upgrade access
        raw += 20 if rules.include?("muster")
        raw += 15 if rules.include?("leader")
        raw += 15 if rules.include?("bannerAura")
        raw += 15 if rules.include?("resoluteAura")
      end
      # Marker-only rules (monster, fast, ranged, wizardAura) have no flat fee.
      [ (raw / 25.0).round * 25, 50 ].max
    end

    def shooting_power(attributes, rules, files, reference_profiles:)
      return 0.0 unless attributes.fetch(:ranged).positive?

      template = attributes.fetch(:shooting_template)
      targets = case template
      when "volley", "common" then files
      when "blast" then rules.include?("heavyBlast") ? 4.5 : 3.0
      when "line" then 3.0
      when "breath" then 3.5
      else 1.0
      end
      # Catapult's blast needs allied fodder: price partial access, not free blast.
      targets = [ targets, 2.0 ].max if rules.include?("slingCatapult")
      power = effective_power(attributes, "shooting", reference_profiles: reference_profiles) * attributes.fetch(:missile_attacks, 1) *
        (attributes.fetch(:skill) / 7.0).clamp(0, 1) * targets
      power *= 1.08 if rules.include?("forestborn")
      power *= 1.20 if rules.include?("outrider")
      power * (attributes.fetch(:shooting_range) / 9.0).clamp(0.25, 2.0)
    end

    # Each normalized seed profile has equal weight, regardless of cost or order.
    # Actual armor, class and abilities also cover new types without a second list.
    def effective_power(attributes, phase, reference_profiles:)
      raise ArgumentError, "reference_profiles must not be empty" if reference_profiles.empty?

      reference_profiles.sum { |target| sample_damage(attributes, target, phase) } * 2.2 / reference_profiles.size
    end

    def incoming_factor(defender, reference_profiles:)
      raise ArgumentError, "reference_profiles must not be empty" if reference_profiles.empty?

      # nil armor uses the engine's neutral multiplier (1), not a named armor type
      # which could itself change during balancing.
      neutral = defender.merge(armor_type: nil, abilities: [])
      received = 0.0
      baseline = 0.0
      reference_profiles.each do |attacker|
        phases = []
        phases << "melee" if attacker.fetch(:melee).positive?
        phases << "shooting" if attacker.fetch(:ranged).positive?
        phases << "magic" if attacker.fetch(:spell).positive? && Array(attacker[:abilities]).include?("wizard")
        phases.each do |phase|
          received += sample_damage(attacker, defender, phase) / phases.size
          baseline += sample_damage(attacker, neutral, phase) / phases.size
        end
      end
      return 1.0 if baseline.zero?

      # Finite estimate even if this population cannot damage the defender.
      [ received / baseline, 0.1 ].max
    end

    def sample_damage(attacker, defender, phase)
      flying = Array(attacker[:abilities]).include?("flying")
      vectors = flying ? { "front" => 0.3, "flank" => 0.4, "rear" => 0.3 } :
        { "front" => 0.7, "flank" => 0.2, "rear" => 0.1 }
      # Ground shooters usually exchange fire head-on; they cannot use melee
      # charge positioning to cross the one-damage threshold.
      vectors = { "front" => 0.9, "flank" => 0.075, "rear" => 0.025 } if phase == "shooting" && !flying
      charges = phase == "melee" ? { 0 => 0.75, attacker.fetch(:movement).clamp(1, 10) => 0.25 } : { 0 => 1.0 }
      vectors.sum do |vector, vector_weight|
        charges.sum do |distance, charge_weight|
          profile = attacker.merge(charged_distance: distance)
          Sim::Battle::Phases::AttackResolution.damage(profile, defender, phase, vector, 1) * vector_weight * charge_weight
        end
      end
    end
  end
end
