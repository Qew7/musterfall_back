module BattlePersistence
  private

  def enrich_battle_payloads_from_snapshot_state(battles_payload, snapshot_state)
    detailed_battles = extract_snapshot_report_battles(snapshot_state)
    return battles_payload if detailed_battles.empty?

    battles_payload.map do |battle_payload|
      detailed_payload = detailed_battles[battle_payload_key(battle_payload)]
      next battle_payload unless detailed_payload

      if battle_payload_actions_count(detailed_payload) > battle_payload_actions_count(battle_payload)
        battle_payload.merge(
          events: detailed_payload.fetch(:events),
          rounds: detailed_payload.fetch(:rounds)
        )
      else
        battle_payload
      end
    end
  end

  def battle_attribute_schema
    [
      :round_number,
      :left_player_id,
      :left_player_name,
      :right_player_id,
      :right_player_name,
      :winner_id,
      :winner_name,
      :summary,
      { events: [] },
      { left_payload: {} },
      { right_payload: {} },
      { rounds: [
        :number,
        { events: [] },
        { turns: [
          :position,
          :player_id,
          :player_name,
          { phases: [
            :position,
            :phase_type,
            :label,
            { events: [] },
            { actions: battle_phase_action_schema }
          ] }
        ] }
      ] }
    ]
  end

  def battle_phase_action_schema
    [
      :type,
      :summary,
      :actor_id,
      :actor_unit_id,
      :actor_name,
      :actor_role,
      :target_id,
      :target_name,
      :vector,
      :damage,
      :requires_line_of_sight,
      { details: [] },
      { blockers: [] },
      { affected_ids: [] },
      { from: battle_position_schema },
      { to: battle_position_schema },
      { actor_state: battle_combatant_state_schema },
      { actor_state_before: battle_combatant_state_schema },
      { actor_state_after: battle_combatant_state_schema },
      { target_state_before: battle_combatant_state_schema },
      { target_state_after: battle_combatant_state_schema },
      { morale_check: battle_morale_check_schema },
      { template: battle_template_schema },
      { charge: battle_charge_schema }
    ]
  end

  def battle_position_schema
    [:x, :y, :facing, :row, :lane]
  end

  def battle_point_schema
    [:x, :y, :facing]
  end

  def battle_combatant_state_schema
    [
      :entity_id,
      :name,
      :kind,
      :side_key,
      :lane,
      :row,
      :x,
      :y,
      :facing,
      :current_health,
      :max_health,
      :model_health,
      :models_remaining,
      :starting_models,
      :frontage,
      :max_files,
      :files,
      :ranks,
      :base_width,
      :base_depth,
      :movement,
      :morale,
      :melee,
      :ranged,
      :spell,
      :is_routing,
      :armor_type,
      :weapon_type,
      { attached_heroes: [:entity_id, :name, :slot] }
    ]
  end

  def battle_template_schema
    [
      :shape,
      :radius,
      :kind,
      :facing,
      { affected_ids: [] },
      { center: battle_point_schema },
      { origin: battle_point_schema },
      { start: battle_point_schema },
      { end: battle_point_schema }
    ]
  end

  def battle_morale_check_schema
    [
      :source_phase,
      :trigger,
      :effective_morale,
      :morale_source,
      :threshold,
      :roll,
      :passed,
      :failure_margin,
      :combat_score_delta,
      :phase_damage,
      :lost_models,
      :starting_models,
      :phase_start_models,
      :threshold_models,
      :status_before,
      :status_after,
      :damage_applied,
      :retreat_edge
    ]
  end

  def battle_charge_schema
    [
      :vector,
      { start: battle_position_schema },
      { destination: battle_position_schema },
      { contact_point: battle_point_schema }
    ]
  end

  def normalize_battle_payload(raw_payload)
    payload = raw_payload.to_h.deep_symbolize_keys
    payload[:round_number] = Integer(payload.fetch(:round_number))
    payload[:events] = payload.fetch(:events)
    payload[:left_payload] = payload.fetch(:left_payload)
    payload[:right_payload] = payload.fetch(:right_payload)
    payload[:rounds] = Array(payload.fetch(:rounds)).map do |round_payload|
      normalized_round = round_payload.deep_symbolize_keys
      normalized_round[:number] = Integer(normalized_round.fetch(:number))
      normalized_round[:events] = normalized_round.fetch(:events)
      normalized_round[:turns] = Array(normalized_round.fetch(:turns)).map.with_index do |turn_payload, turn_index|
        normalized_turn = turn_payload.deep_symbolize_keys
        normalized_turn[:position] = Integer(normalized_turn[:position] || turn_index)
        normalized_turn[:phases] = Array(normalized_turn.fetch(:phases)).map.with_index do |phase_payload, phase_index|
          normalized_phase = phase_payload.deep_symbolize_keys
          normalized_phase[:position] = Integer(normalized_phase[:position] || phase_index)
          normalized_phase[:events] = normalized_phase.fetch(:events)
          normalized_phase[:actions] = Array(normalized_phase[:actions]).map { |action_payload| normalize_battle_action_payload(action_payload) }
          normalized_phase
        end
        normalized_turn
      end
      normalized_round
    end
    payload
  end

  def normalize_battle_action_payload(raw_action_payload)
    payload = raw_action_payload.to_h.deep_symbolize_keys
    payload[:damage] = Integer(payload[:damage]) if payload.key?(:damage) && !payload[:damage].nil?
    payload[:requires_line_of_sight] = ActiveModel::Type::Boolean.new.cast(payload[:requires_line_of_sight]) if payload.key?(:requires_line_of_sight)
    payload[:details] = Array(payload[:details]) if payload.key?(:details)
    payload[:blockers] = Array(payload[:blockers]) if payload.key?(:blockers)
    payload[:affected_ids] = Array(payload[:affected_ids]) if payload.key?(:affected_ids)
    payload[:morale_check] = normalize_battle_morale_check_payload(payload[:morale_check]) if payload[:morale_check].present?

    %i[from to].each do |key|
      payload[key] = normalize_battle_position_payload(payload[key]) if payload[key].present?
    end

    %i[actor_state actor_state_before actor_state_after target_state_before target_state_after].each do |key|
      payload[key] = normalize_battle_combatant_state_payload(payload[key]) if payload[key].present?
    end

    payload[:template] = normalize_battle_template_payload(payload[:template]) if payload[:template].present?
    payload[:charge] = normalize_battle_charge_payload(payload[:charge]) if payload[:charge].present?
    payload.compact
  end

  def extract_snapshot_report_battles(snapshot_state)
    state_payload = snapshot_state.to_h.deep_symbolize_keys
    campaign = state_payload[:campaign]
    return {} unless campaign

    report = campaign[:lastRoundReport] || campaign[:last_round_report]
    return {} unless report

    round_number = Integer(report.fetch(:round) || report.fetch(:round_number))

    Array(report[:matchups]).each_with_object({}) do |matchup_payload, result|
      normalized_payload = normalize_battle_payload(build_battle_payload_from_snapshot_report(matchup_payload, round_number))
      result[battle_payload_key(normalized_payload)] = normalized_payload
    end
  end

  def build_battle_payload_from_snapshot_report(raw_payload, round_number)
    payload = raw_payload.to_h.deep_symbolize_keys

    {
      round_number: round_number,
      left_player_id: payload.dig(:left, :playerId),
      left_player_name: payload.dig(:left, :playerName),
      right_player_id: payload.dig(:right, :playerId),
      right_player_name: payload.dig(:right, :playerName),
      winner_id: payload.fetch(:winnerId),
      winner_name: payload.fetch(:winnerName),
      summary: payload.fetch(:summary),
      events: Array(payload[:events]),
      left_payload: payload.fetch(:left),
      right_payload: payload.fetch(:right),
      rounds: Array(payload[:rounds]).map.with_index do |round_payload, round_index|
        build_round_payload_from_snapshot_report(round_payload, round_index)
      end
    }
  end

  def build_round_payload_from_snapshot_report(raw_payload, round_index)
    payload = raw_payload.to_h.deep_symbolize_keys

    {
      number: Integer(payload.fetch(:number) || round_index + 1),
      events: Array(payload[:events]),
      turns: Array(payload[:turns]).map.with_index do |turn_payload, turn_index|
        build_turn_payload_from_snapshot_report(turn_payload, turn_index)
      end
    }
  end

  def build_turn_payload_from_snapshot_report(raw_payload, turn_index)
    payload = raw_payload.to_h.deep_symbolize_keys

    {
      position: Integer(payload[:position] || turn_index),
      player_id: payload.fetch(:playerId),
      player_name: payload.fetch(:playerName),
      phases: Array(payload[:phases]).map.with_index do |phase_payload, phase_index|
        build_phase_payload_from_snapshot_report(phase_payload, phase_index)
      end
    }
  end

  def build_phase_payload_from_snapshot_report(raw_payload, phase_index)
    payload = raw_payload.to_h.deep_symbolize_keys

    {
      position: Integer(payload[:position] || phase_index),
      phase_type: payload.fetch(:type),
      label: payload.fetch(:label),
      events: Array(payload[:events]),
      actions: Array(payload[:actions]).map { |action_payload| build_action_payload_from_snapshot_report(action_payload) }
    }
  end

  def build_action_payload_from_snapshot_report(raw_payload)
    payload = raw_payload.to_h.deep_symbolize_keys

    {
      type: payload[:type],
      summary: payload[:summary],
      details: Array(payload[:details]),
      actor_id: payload[:actorId],
      actor_unit_id: payload[:actorUnitId],
      actor_name: payload[:actorName],
      actor_role: payload[:actorRole],
      target_id: payload[:targetId],
      target_name: payload[:targetName],
      vector: payload[:vector],
      damage: payload[:damage],
      requires_line_of_sight: payload[:requiresLineOfSight],
      blockers: Array(payload[:blockers]),
      affected_ids: Array(payload[:affectedIds]),
      from: build_position_payload_from_snapshot_report(payload[:from]),
      to: build_position_payload_from_snapshot_report(payload[:to]),
      actor_state: build_combatant_state_payload_from_snapshot_report(payload[:actorState]),
      actor_state_before: build_combatant_state_payload_from_snapshot_report(payload[:actorStateBefore]),
      actor_state_after: build_combatant_state_payload_from_snapshot_report(payload[:actorStateAfter]),
      target_state_before: build_combatant_state_payload_from_snapshot_report(payload[:targetStateBefore]),
      target_state_after: build_combatant_state_payload_from_snapshot_report(payload[:targetStateAfter]),
      morale_check: build_morale_check_payload_from_snapshot_report(payload[:moraleCheck]),
      template: build_template_payload_from_snapshot_report(payload[:template]),
      charge: build_charge_payload_from_snapshot_report(payload[:charge])
    }.compact
  end

  def build_position_payload_from_snapshot_report(raw_payload)
    return nil unless raw_payload

    payload = raw_payload.to_h.deep_symbolize_keys
    {
      x: payload[:x],
      y: payload[:y],
      facing: payload[:facing],
      row: payload[:row],
      lane: payload[:lane]
    }.compact
  end

  def build_point_payload_from_snapshot_report(raw_payload)
    return nil unless raw_payload

    payload = raw_payload.to_h.deep_symbolize_keys
    {
      x: payload[:x],
      y: payload[:y],
      facing: payload[:facing]
    }.compact
  end

  def build_combatant_state_payload_from_snapshot_report(raw_payload)
    return nil unless raw_payload

    payload = raw_payload.to_h.deep_symbolize_keys
    {
      entity_id: payload[:entityId],
      name: payload[:name],
      kind: payload[:kind],
      side_key: payload[:sideKey],
      lane: payload[:lane],
      row: payload[:row],
      x: payload[:x],
      y: payload[:y],
      facing: payload[:facing],
      current_health: payload[:currentHealth],
      max_health: payload[:maxHealth],
      model_health: payload[:modelHealth],
      models_remaining: payload[:modelsRemaining],
      starting_models: payload[:startingModels],
      frontage: payload[:frontage],
      max_files: payload[:maxFiles],
      files: payload[:files],
      ranks: payload[:ranks],
      base_width: payload[:baseWidth],
      base_depth: payload[:baseDepth],
      movement: payload[:movement],
      morale: payload[:morale],
      melee: payload[:melee],
      ranged: payload[:ranged],
      spell: payload[:spell],
      is_routing: payload[:isRouting],
      armor_type: payload[:armorType],
      weapon_type: payload[:weaponType],
      attached_heroes: Array(payload[:attachedHeroes]).filter_map do |hero_payload|
        next unless hero_payload.respond_to?(:to_h)

        hero = hero_payload.to_h.deep_symbolize_keys
        {
          entity_id: hero[:entityId],
          name: hero[:name],
          slot: hero[:slot]
        }.compact
      end
    }.compact
  end

  def build_template_payload_from_snapshot_report(raw_payload)
    return nil unless raw_payload

    payload = raw_payload.to_h.deep_symbolize_keys
    {
      shape: payload[:shape],
      radius: payload[:radius],
      kind: payload[:kind],
      facing: payload[:facing],
      affected_ids: Array(payload[:affectedIds]),
      center: build_point_payload_from_snapshot_report(payload[:center]),
      origin: build_point_payload_from_snapshot_report(payload[:origin]),
      start: build_point_payload_from_snapshot_report(payload[:start]),
      end: build_point_payload_from_snapshot_report(payload[:end])
    }.compact
  end

  def build_charge_payload_from_snapshot_report(raw_payload)
    return nil unless raw_payload

    payload = raw_payload.to_h.deep_symbolize_keys
    {
      vector: payload[:vector],
      start: build_position_payload_from_snapshot_report(payload[:start]),
      destination: build_position_payload_from_snapshot_report(payload[:destination]),
      contact_point: build_point_payload_from_snapshot_report(payload[:contactPoint] || payload[:contact_point])
    }.compact
  end

  def build_morale_check_payload_from_snapshot_report(raw_payload)
    return nil unless raw_payload

    payload = raw_payload.to_h.deep_symbolize_keys
    {
      source_phase: payload[:sourcePhase],
      trigger: payload[:trigger],
      effective_morale: payload[:effectiveMorale],
      morale_source: payload[:moraleSource],
      threshold: payload[:threshold],
      roll: payload[:roll],
      passed: payload[:passed],
      failure_margin: payload[:failureMargin],
      combat_score_delta: payload[:combatScoreDelta],
      phase_damage: payload[:phaseDamage],
      lost_models: payload[:lostModels],
      starting_models: payload[:startingModels],
      phase_start_models: payload[:phaseStartModels],
      threshold_models: payload[:thresholdModels],
      status_before: payload[:statusBefore],
      status_after: payload[:statusAfter],
      damage_applied: payload[:damageApplied],
      retreat_edge: payload[:retreatEdge]
    }.compact
  end

  def battle_payload_key(payload)
    [
      payload.fetch(:round_number),
      payload.fetch(:left_player_id),
      payload.fetch(:right_player_id)
    ]
  end

  def battle_payload_actions_count(payload)
    Array(payload[:rounds]).sum do |round_payload|
      Array(round_payload[:turns]).sum do |turn_payload|
        Array(turn_payload[:phases]).sum do |phase_payload|
          Array(phase_payload[:actions]).size
        end
      end
    end
  end

  def normalize_battle_position_payload(raw_position_payload)
    payload = raw_position_payload.to_h.deep_symbolize_keys
    payload[:x] = Float(payload[:x]) if payload.key?(:x) && !payload[:x].nil?
    payload[:y] = Float(payload[:y]) if payload.key?(:y) && !payload[:y].nil?
    payload[:facing] = Integer(payload[:facing]) if payload.key?(:facing) && !payload[:facing].nil?
    payload.compact
  end

  def normalize_battle_point_payload(raw_point_payload)
    payload = raw_point_payload.to_h.deep_symbolize_keys
    payload[:x] = Float(payload[:x]) if payload.key?(:x) && !payload[:x].nil?
    payload[:y] = Float(payload[:y]) if payload.key?(:y) && !payload[:y].nil?
    payload[:facing] = Integer(payload[:facing]) if payload.key?(:facing) && !payload[:facing].nil?
    payload.compact
  end

  def normalize_battle_combatant_state_payload(raw_state_payload)
    payload = raw_state_payload.to_h.deep_symbolize_keys

    %i[x y base_width base_depth].each do |key|
      payload[key] = Float(payload[key]) if payload.key?(key) && !payload[key].nil?
    end

    %i[
      facing
      current_health
      max_health
      model_health
      models_remaining
      starting_models
      frontage
      max_files
      files
      ranks
      movement
      morale
      melee
      ranged
      spell
    ].each do |key|
      payload[key] = Integer(payload[key]) if payload.key?(key) && !payload[key].nil?
    end

    payload[:is_routing] = ActiveModel::Type::Boolean.new.cast(payload[:is_routing]) if payload.key?(:is_routing)

    payload[:attached_heroes] = Array(payload[:attached_heroes]).map do |hero_payload|
      hero_payload.to_h.deep_symbolize_keys.compact
    end

    payload.compact
  end

  def normalize_battle_morale_check_payload(raw_morale_check_payload)
    payload = raw_morale_check_payload.to_h.deep_symbolize_keys

    %i[
      effective_morale
      threshold
      roll
      failure_margin
      combat_score_delta
      phase_damage
      lost_models
      starting_models
      phase_start_models
      threshold_models
      damage_applied
    ].each do |key|
      payload[key] = Integer(payload[key]) if payload.key?(key) && !payload[key].nil?
    end

    %i[passed status_before status_after].each do |key|
      payload[key] = ActiveModel::Type::Boolean.new.cast(payload[key]) if payload.key?(key)
    end

    payload.compact
  end

  def normalize_battle_template_payload(raw_template_payload)
    payload = raw_template_payload.to_h.deep_symbolize_keys
    payload[:radius] = Float(payload[:radius]) if payload.key?(:radius) && !payload[:radius].nil?
    payload[:facing] = Integer(payload[:facing]) if payload.key?(:facing) && !payload[:facing].nil?
    payload[:affected_ids] = Array(payload[:affected_ids]) if payload.key?(:affected_ids)

    %i[center origin start end].each do |key|
      payload[key] = normalize_battle_point_payload(payload[key]) if payload[key].present?
    end

    payload.compact
  end

  def normalize_battle_charge_payload(raw_charge_payload)
    payload = raw_charge_payload.to_h.deep_symbolize_keys
    payload[:start] = normalize_battle_position_payload(payload[:start]) if payload[:start].present?
    payload[:destination] = normalize_battle_position_payload(payload[:destination]) if payload[:destination].present?
    payload[:contact_point] = normalize_battle_point_payload(payload[:contact_point]) if payload[:contact_point].present?
    payload.compact
  end

  def persist_battle!(game, payload)
    battle = game.battles.find_or_initialize_by(
      round_number: payload.fetch(:round_number),
      left_player_id: payload.fetch(:left_player_id),
      right_player_id: payload.fetch(:right_player_id)
    )

    assign_battle_attributes(battle, payload)
    battle.save!
    replace_rounds!(battle, payload.fetch(:rounds))
    battle
  end

  def assign_battle_attributes(battle, payload)
    battle.assign_attributes(
      left_player_name: payload.fetch(:left_player_name),
      right_player_name: payload.fetch(:right_player_name),
      winner_id: payload.fetch(:winner_id),
      winner_name: payload.fetch(:winner_name),
      summary: payload.fetch(:summary),
      left_payload: payload.fetch(:left_payload),
      right_payload: payload.fetch(:right_payload),
      events: payload.fetch(:events)
    )
  end

  def replace_rounds!(battle, rounds_payload)
    battle.battle_rounds.destroy_all

    rounds_payload.each do |round_payload|
      battle_round = battle.battle_rounds.create!(
        number: round_payload.fetch(:number),
        events: round_payload.fetch(:events)
      )

      Array(round_payload.fetch(:turns)).each do |turn_payload|
        battle_turn = battle_round.battle_turns.create!(
          position: turn_payload.fetch(:position),
          player_id: turn_payload.fetch(:player_id),
          player_name: turn_payload.fetch(:player_name)
        )

        Array(turn_payload.fetch(:phases)).each do |phase_payload|
          battle_turn.battle_phases.create!(
            position: phase_payload.fetch(:position),
            phase_type: phase_payload.fetch(:phase_type),
            label: phase_payload.fetch(:label),
            events: phase_payload.fetch(:events),
            actions: phase_payload.fetch(:actions, [])
          )
        end
      end
    end
  end
end