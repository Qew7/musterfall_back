# frozen_string_literal: true

# Last N completed matchups: true OBB overlap of living trays vs impassable
# terrain and vs each other. Uses stored result_payload snapshots, not a re-sim.
#
#   bin/rails runner script/profilers/scan_overlaps.rb 15
#   docker exec musterfall-backend-1 bin/rails runner script/profilers/scan_overlaps.rb 15
#   bin/rails runner script/profilers/scan_overlaps.rb --self-check

module ScanOverlaps
  Obb = Sim::Geometry::Obb
  Battlefield = Sim::Geometry::Battlefield

  module_function

  def cli(argv)
    if argv.include?("--self-check")
      self_check!
      return
    end

    limit = Integer(argv.find { |arg| arg.match?(/\A\d+\z/) } || ENV.fetch("LIMIT", "10"))
    json = argv.include?("--json") || ENV["JSON"] == "1"
    reports = scan_recent(limit)
    if json
      puts JSON.pretty_generate(reports)
    else
      print_reports(reports)
    end
  end

  def self_check!
    house = {
      id: "house", type: "house", x: 10.0, y: 10.0, width: 4.0, depth: 4.0, impassable: true
    }
    stuck = unit("a", "Stuck", x: 10.0, y: 10.0)
    left = unit("b", "Left", x: 30.0, y: 12.0)
    right = unit("c", "Right", x: 30.4, y: 12.0)
    hits = hits_at({ "a" => stuck, "b" => left, "c" => right }, [ house ])
    kinds = hits.map { |hit| hit[:kind] }.uniq.sort
    raise "self-check: #{kinds.inspect}" unless kinds == %w[terrain unit]

    expect_layer("deploy", nil, %w[a], "deploy")
    expect_layer("R1 morale A1", { type: "morale", actor_id: "a", from: pos(0, 0, 0), to: pos(2, 0, 180) }, %w[a], "flee")
    expect_layer("R1 movement A1", move_action(heading: 0, desired_facing: 90, to_facing: 90), %w[a], "follow")
    expect_layer(
      "R1 movement A1",
      move_action(truncated: true, budget: 4, spent_advance: 1, to_x: 0.2),
      %w[a],
      "maneuver"
    )
    expect_layer("R1 movement A1", move_action(mode: "flyer_charge", to_x: 2), %w[a], "flyer")
    expect_layer("R1 movement A1", move_action(to_x: 2), %w[a], "obstacles")

    puts "self-check ok"
  end

  def scan_recent(limit)
    rows = RoundMatchup.where(status: "completed").order(id: :desc).limit(limit * 4)
    picked = []
    rows.each do |matchup|
      payload = Sim::Campaign::State.deep_symbolize(matchup.result_payload || {})
      next if Array(payload[:rounds]).empty? || Array(payload[:initial_snapshot]).empty?

      picked << scan_payload(matchup, payload)
      break if picked.size >= limit
    end
    {
      scanned: picked.size,
      requested: limit,
      incidents: picked.sum { |row| row[:incidents].size },
      matchups: picked
    }
  end

  def scan_payload(matchup, payload)
    units = index_units(payload[:initial_snapshot])
    terrain = Array(payload[:terrain]).map { |feature| feature.dup }
    open = {}
    closed = []

    observe!(open, closed, units, terrain, "deploy", nil)
    Array(payload[:rounds]).each do |round|
      Array(round[:turns]).each do |turn|
        Array(turn[:phases]).each do |phase|
          apply_terrain_delta!(terrain, phase[:terrain_delta])
          actions = Array(phase[:actions])
          actions.each_with_index do |action, index|
            apply_terrain_delta!(terrain, action[:terrain_delta])
            apply_action!(units, action)
            label = point(round, phase, index + 1)
            observe!(open, closed, units, terrain, label, action)
          end
          next if actions.any? || phase[:snapshot].blank?

          apply_snapshot!(units, phase[:snapshot])
          observe!(open, closed, units, terrain, point(round, phase, 0), nil)
        end
      end
    end
    closed.concat(open.values)

    {
      matchup_id: matchup.id,
      battle_id: battle_id_for(matchup),
      game_id: matchup.game_id,
      campaign_round: matchup.campaign_round,
      seed: matchup.seed,
      players: "#{matchup.attacker_player_name} vs #{matchup.defender_player_name}",
      units: units.size,
      terrain: terrain.size,
      incidents: closed
    }
  end

  def observe!(open, closed, units, terrain, label, action)
    current = {}
    hits_at(units, terrain).each do |hit|
      rec = hit.merge(at: label)
      ids = [ hit[:left][:id], hit[:right][:id] ]
      actor = action && (action[:actor_id] || action[:target_id])
      rec[:summary] = action[:summary] if action && ids.include?(actor)
      rec[:move] = opening_fields(label, action, ids)
      current[hit[:key]] = rec
    end
    open.keys.each do |key|
      next if current[key]

      closed << open.delete(key)
    end
    current.each do |key, rec|
      if open[key]
        open[key][:last] = label
        open[key][:ticks] += 1
      else
        open[key] = rec.merge(first: label, last: label, ticks: 1)
      end
    end
  end

  def opening_fields(label, action, ids)
    return { layer: "deploy" } if label == "deploy"
    return {} unless action && ids.include?(action[:actor_id])

    man = action[:maneuver] || {}
    from = action[:from]
    to = action[:to]
    dxy = from && to ? Battlefield.distance_between(from, to) : nil
    leftover = leftover_of(man)
    heading = man[:heading]
    desired_face = man.dig(:desired, :facing)
    df = from && to ? Battlefield.shortest_facing_delta(from[:facing], to[:facing]) : nil
    fields = {
      type: action[:type].to_s.presence,
      kind: man[:kind],
      approach_mode: man[:approach_mode],
      truncated: man[:truncated_by_collision],
      blocked_by_ally: man[:blocked_by_ally],
      blocker_id: man[:blocker_id],
      blocker_name: man[:blocker_name],
      heading: heading&.to_f&.round(1),
      desired_facing: desired_face&.to_f&.round(1),
      dxy: dxy&.round(2),
      leftover: leftover&.round(2),
      budget: man[:mv_budget]&.to_f&.round(2),
      steps: Array(man[:steps]).filter_map { |step| step[:kind]&.to_s.presence },
      from: pose_short(from),
      to: pose_short(to)
    }
    fields[:layer] = infer_layer(
      type: fields[:type],
      man: man,
      dxy: dxy,
      leftover: leftover,
      df: df,
      heading: heading,
      desired_face: desired_face
    )
    fields.compact
  end

  # ponytail: first-action heuristics only; Thread wrap vertices are not persisted.
  def infer_layer(type:, man:, dxy:, leftover:, df:, heading:, desired_face:)
    return "flee" if type == "morale"
    return "flyer" if man[:approach_mode].to_s.start_with?("flyer")
    if df && df.abs >= 80 && !heading.nil? && !desired_face.nil? &&
        Battlefield.shortest_facing_delta(heading, desired_face).abs >= 60
      return "follow"
    end
    return "maneuver" if man[:truncated_by_collision] && leftover.to_f > 0.5
    return "maneuver" if man[:blocker_is_target] || man[:kind].to_s == "contact_align"
    return "obstacles" if type == "movement" && !man[:truncated_by_collision] && dxy.to_f > 0.05

    nil
  end

  def leftover_of(man)
    return nil if man[:mv_budget].nil?

    spent = %i[mv_spent_wheel mv_spent_turn mv_spent_advance mv_spent_march].sum { |key| man[key].to_f }
    man[:mv_budget].to_f - spent
  end

  def pose_short(pose)
    return nil unless pose && !pose[:x].nil?

    [ pose[:x].to_f.round(2), pose[:y].to_f.round(2), pose[:facing].to_f.round(1) ]
  end

  def expect_layer(label, action, ids, want)
    got = opening_fields(label, action, ids)[:layer]
    raise "self-check layer #{want.inspect} got #{got.inspect}" unless got == want
  end

  def pos(x, y, facing)
    { x: x, y: y, facing: facing }
  end

  def move_action(heading: 0, desired_facing: 0, to_facing: 0, to_x: 0, truncated: false, budget: nil, spent_advance: 0, mode: nil)
    {
      type: "movement",
      actor_id: "a",
      from: pos(0, 0, 0),
      to: pos(to_x, 0, to_facing),
      maneuver: {
        kind: "reposition",
        heading: heading,
        desired: { facing: desired_facing },
        truncated_by_collision: truncated,
        approach_mode: mode,
        mv_budget: budget,
        mv_spent_advance: spent_advance,
        steps: [ { kind: "advance" } ]
      }
    }
  end

  def hits_at(units, terrain)
    living = living_units(units)
    obstacles = Battlefield.impassable_obstacles(terrain)
    hits = []
    living.each do |combatant|
      obstacles.each do |obs|
        next unless Obb.overlap_units?(combatant, obs)

        hits << {
          kind: "terrain",
          key: "T:#{combatant[:entity_id]}|#{obs[:entity_id]}",
          left: describe(combatant),
          right: describe_feature(obs)
        }
      end
    end
    # ponytail: n² over living trays (~10–20); spatial index if a matchup ever dwarfs that.
    living.combination(2).each do |left, right|
      next unless Obb.overlap_units?(left, right)

      ids = [ left[:entity_id], right[:entity_id] ].sort
      hits << {
        kind: "unit",
        key: "U:#{ids.join('|')}",
        left: describe(left),
        right: describe(right)
      }
    end
    hits
  end

  def apply_action!(units, action)
    if action[:snapshot]
      apply_snapshot!(units, action[:snapshot])
      return
    end

    patch_unit!(units, action[:actor_id], action[:actor_state_after], action[:to])
    patch_unit!(units, action[:target_id], action[:target_state_after], nil)
  end

  def apply_snapshot!(units, snapshot)
    units.replace(index_units(snapshot))
  end

  def patch_unit!(units, id, after, pose)
    return unless id

    base = units[id] || { entity_id: id }
    base = base.merge(after) if after
    if pose
      base[:x] = pose[:x] unless pose[:x].nil?
      base[:y] = pose[:y] unless pose[:y].nil?
      base[:facing] = pose[:facing] unless pose[:facing].nil?
    end
    units[id] = base.merge(entity_id: id)
  end

  def apply_terrain_delta!(terrain, delta)
    Array(delta).each do |change|
      feature = change[:feature] || {}
      id = feature[:id]
      case change[:operation].to_s
      when "add"
        terrain << feature if id && terrain.none? { |entry| entry[:id] == id }
      when "remove"
        terrain.reject! { |entry| entry[:id] == id }
      end
    end
  end

  def index_units(list)
    Array(list).each_with_object({}) do |entry, hash|
      id = entry[:entity_id] || entry[:id]
      next unless id

      hash[id] = entry.merge(entity_id: id)
    end
  end

  def living_units(units)
    units.values.select { |entry| entry[:current_health].to_i.positive? && !entry[:x].nil? }
  end

  def describe(unit)
    {
      id: unit[:entity_id],
      name: unit[:name],
      side: unit[:side_key],
      x: unit[:x].to_f.round(2),
      y: unit[:y].to_f.round(2),
      facing: unit[:facing].to_f.round(1),
      width: unit[:base_width].to_f.round(2),
      depth: unit[:base_depth].to_f.round(2)
    }
  end

  def describe_feature(obs)
    {
      id: obs[:entity_id],
      name: obs[:name] || obs[:terrain_type],
      type: obs[:terrain_type],
      x: obs[:x].to_f.round(2),
      y: obs[:y].to_f.round(2),
      width: obs[:base_width].to_f.round(2),
      depth: obs[:base_depth].to_f.round(2)
    }
  end

  def point(round, phase, action_index)
    kind = phase[:type] || phase[:phase_type]
    "R#{round[:number]} #{kind} A#{action_index}"
  end

  def battle_id_for(matchup)
    keys = [ matchup.attacker_player_key, matchup.defender_player_key ].sort
    Battle.where(game_id: matchup.game_id, round_number: matchup.campaign_round)
      .find { |row| [ row.left_player_id, row.right_player_id ].sort == keys }
      &.id
  end

  def unit(id, name, x:, y:)
    {
      entity_id: id, name: name, x: x, y: y, facing: 0.0,
      base_width: 2.0, base_depth: 2.0, current_health: 1
    }
  end

  def print_reports(bundle)
    puts "scanned=#{bundle[:scanned]}/#{bundle[:requested]} incidents=#{bundle[:incidents]}"
    bundle[:matchups].each do |row|
      puts "\n=== matchup #{row[:matchup_id]} battle=#{row[:battle_id]} " \
           "game=#{row[:game_id]} r#{row[:campaign_round]} seed=#{row[:seed]} #{row[:players]} ==="
      if row[:incidents].empty?
        puts "  clean"
        next
      end
      row[:incidents].each { |hit| puts "  #{format_hit(hit)}" }
    end
  end

  def format_hit(hit)
    extra = compact_move(hit[:move])
    extra = extra.empty? ? "" : " #{extra}"
    "#{hit[:kind]} #{hit[:first]}..#{hit[:last]} ticks=#{hit[:ticks]} " \
      "#{fmt(hit[:left])} ∩ #{fmt(hit[:right])}#{extra}" \
      "#{hit[:summary] ? "\n    #{hit[:summary]}" : ''}"
  end

  def compact_move(move)
    return "" if move.blank?

    parts = []
    parts << "layer=#{move[:layer]}" if move[:layer]
    parts << "type=#{move[:type]}" if move[:type] && move[:type] != "movement"
    parts << "kind=#{move[:kind]}" if move[:kind]
    parts << "mode=#{move[:approach_mode]}" if move[:approach_mode]
    parts << "Δxy=#{move[:dxy]}" unless move[:dxy].nil?
    if move[:leftover] && move[:budget]
      parts << "left=#{move[:leftover]}/#{move[:budget]}"
    elsif move[:leftover]
      parts << "left=#{move[:leftover]}"
    end
    parts << "trunc" if move[:truncated]
    parts << "ally" if move[:blocked_by_ally]
    parts << "blk=#{move[:blocker_name]}" if move[:blocker_name]
    parts << "heading=#{move[:heading]}" unless move[:heading].nil?
    parts << "des=#{move[:desired_facing]}" unless move[:desired_facing].nil?
    parts << "steps=#{move[:steps].join('+')}" if move[:steps]&.any?
    if move[:from] && move[:to]
      parts << "#{fmt_xyz(move[:from])}->#{fmt_xyz(move[:to])}"
    end
    parts.join(" ")
  end

  def fmt_xyz(xyz)
    "(#{xyz[0]},#{xyz[1]})f#{xyz[2]}"
  end

  def fmt(entry)
    pose = "(#{entry[:x]},#{entry[:y]})"
    pose = "#{pose} f#{entry[:facing]}" unless entry[:facing].nil?
    "#{entry[:name]}(#{entry[:id]}) #{pose} #{entry[:width]}x#{entry[:depth]}"
  end
end

ScanOverlaps.cli(ARGV)
