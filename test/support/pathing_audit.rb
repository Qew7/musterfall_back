# Quality bar for thread pathing.
# Linus — one pipeline: taut OBB thread, then declared maneuvers. No heading probes.
# Dijkstra — collision-true segments; wrap vertices keep the moving tray off obstacles.
# Maneuver — wheel/turn then advance/march along the thread; contact is a face.
module PathingAudit
  ROOT = File.expand_path("../../app/domain/sim/battle", __dir__)
  PATHING = File.join(ROOT, "pathing.rb")
  MANEUVERS = File.join(ROOT, "pathing/maneuvers.rb")
  BAR = { linus: 95, dijkstra: 95, maneuver: 100 }.freeze

  ANTIPATTERNS = [
    {
      id: :heading_probe_bypass,
      file: PATHING,
      pattern: /BYPASS_HEADING_OFFSETS/,
      reviewers: { linus: 16, dijkstra: 8, maneuver: 12 },
      message: "heading-offset bypass survived the thread rewrite"
    },
    {
      id: :competitive_maneuver_pick,
      file: MANEUVERS,
      pattern: /def pick\(/,
      reviewers: { linus: 14, dijkstra: 4, maneuver: 10 },
      message: "maneuvers still compete instead of following the thread"
    },
    {
      id: :hold_column_ally,
      file: PATHING,
      pattern: /ally_bypass_allowed\?/,
      reviewers: { linus: 8, dijkstra: 2, maneuver: 8 },
      message: "hold-column ally special case survived the thread rewrite"
    }
  ].freeze

  Report = Struct.new(
    :linus, :dijkstra, :maneuver, :issues, :runtime, :meets_bar?,
    keyword_init: true
  )

  module_function

  def report
    issues = source_issues
    runtime = runtime_issues
    all = issues + runtime
    scores = {
      linus: score_for(:linus, all),
      dijkstra: score_for(:dijkstra, all),
      maneuver: score_for(:maneuver, all)
    }
    Report.new(
      linus: scores[:linus],
      dijkstra: scores[:dijkstra],
      maneuver: scores[:maneuver],
      issues: all,
      runtime: runtime,
      meets_bar?: scores[:linus] >= BAR[:linus] &&
        scores[:dijkstra] >= BAR[:dijkstra] &&
        scores[:maneuver] >= BAR[:maneuver]
    )
  end

  def source_issues
    ANTIPATTERNS.filter_map do |rule|
      next unless File.exist?(rule[:file])

      text = File.read(rule[:file])
      next unless text.match?(rule[:pattern])

      issue(rule[:id], rule[:message], rule[:reviewers], file: File.basename(rule[:file]))
    end
  end

  def runtime_issues
    house_thread_issues + wall_segment_issues + execution_issues + center_lake_wheel_issues
  end

  def score_for(reviewer, issues)
    penalty = issues.sum { |entry| entry[:reviewers][reviewer].to_i }
    [ 100 - penalty, 0 ].max
  end

  def issue(id, message, reviewers, file: nil)
    { id: id, message: message, reviewers: reviewers, file: file }
  end

  def house_thread_issues
    actor = BattleScenarios.combatant(x: 6.0, y: 8.0, facing: 0.0, movement: 5.0)
    target = BattleScenarios.enemy(x: 31.0, y: 8.0, facing: 180.0)
    house = BattleScenarios.terrain(id: "house", x: 18.0, y: 8.0, width: 3.0, depth: 3.0)
    obstacles = Sim::Battle::Pathing.merge_obstacles([ actor, target ], [ house ])
    kernels = Sim::Battle::Pathing.obstacle_kernels(obstacles)
    thread = Sim::Battle::Pathing::Thread.pull(
      mover: actor, goal: target, obstacles: obstacles, contact_id: target[:entity_id], kernels: kernels
    )
    issues = []
    unless thread && thread[:points] && thread[:points].length >= 2
      return [ issue(:no_house_thread, "thread does not wrap a 3\" house",
                     { linus: 4, dijkstra: 20, maneuver: 16 }) ]
    end

    house_obs = Sim::Geometry::Battlefield.feature_as_obstacle(house)
    collided = thread[:points].any? do |point|
      pose = actor.merge(x: point[:x], y: point[:y])
      Sim::Geometry::Battlefield.rectangles_overlap?(pose, house_obs)
    end
    if collided
      issues << issue(:thread_hits_house, "thread vertices overlap the house",
                      { linus: 4, dijkstra: 18, maneuver: 16 })
    end
    issues
  end

  def wall_segment_issues
    actor = BattleScenarios.combatant(x: 2.0, y: 12.0, facing: 0.0)
    target = { x: 36.0, y: 12.0 }
    wall = BattleScenarios.terrain(id: "wall", x: 20.0, y: 12.0, width: 1.0, depth: 4.0)
    obstacles = Sim::Battle::Pathing.merge_obstacles([ actor ], [ wall ])
    kernels = Sim::Battle::Pathing.obstacle_kernels(obstacles)
    clear = Sim::Battle::Pathing::Thread.segment_clear?(actor, actor, target, kernels, nil)
    return [] unless clear

    [ issue(:segment_skips_wall, "thread segment_clear? misses a 1\" wall on a long line",
            { linus: 4, dijkstra: 18, maneuver: 12 }) ]
  end

  def wide_lake
    BattleScenarios.terrain(
      id: "lake", type: "lake", x: 14.55, y: 18.38, width: 5.382, depth: 3.897, impassable: true
    )
  end

  def execution_issues
    actor = BattleScenarios.combatant(
      x: 8.0, y: 20.0, facing: 0.0, movement: 4.0, base_width: 5.0, base_depth: 2.0
    )
    target = BattleScenarios.enemy(x: 35.0, y: 19.0, facing: 180.0, base_width: 4.0, base_depth: 4.0)
    lake = wide_lake
    obstacles = Sim::Battle::Pathing.merge_obstacles([ actor, target ], [ lake ])
    plan = Sim::Battle::Pathing.plan_approach(
      origin: actor,
      goal_point: target,
      budget: 6.0,
      obstacles: obstacles,
      contact_id: target[:entity_id],
      goal_unit: target,
      terrain: [ lake ]
    )
    issues = []
    unless plan && plan[:pose]
      return [ issue(:lake_no_pose, "wide unit against a lake produces no legal pose",
                     { linus: 6, dijkstra: 8, maneuver: 20 }) ]
    end

    lake_obs = Sim::Geometry::Battlefield.feature_as_obstacle(lake)
    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    if Sim::Geometry::Battlefield.rectangles_overlap?(landed, lake_obs)
      issues << issue(:lands_in_lake, "approach lands overlapping impassable terrain",
                      { linus: 8, dijkstra: 10, maneuver: 24 })
    end
    issues
  end

  def center_lake_wheel_issues
    actor = BattleScenarios.combatant(
      entity_id: "guard", x: 8.0, y: 12.0, facing: 0.0,
      base_width: 5.0, base_depth: 2.0, movement: 3.0
    )
    target = BattleScenarios.enemy(
      entity_id: "enemy", x: 31.0, y: 12.0, facing: 180.0, base_width: 4.0, base_depth: 3.0
    )
    lake = BattleScenarios.terrain(
      id: "lake", type: "lake", x: 14.7, y: 10.2, width: 3.072, depth: 3.096, impassable: true
    )
    lake_obs = Sim::Geometry::Battlefield.feature_as_obstacle(lake)
    obstacles = Sim::Battle::Pathing.merge_obstacles([ actor, target ], [ lake ])
    plan = Sim::Battle::Pathing.plan_approach(
      origin: actor, goal_point: target, budget: 6.0,
      obstacles: obstacles, contact_id: target[:entity_id], goal_unit: target, terrain: [ lake ]
    )
    issues = []
    unless plan && plan[:pose]
      return [ issue(:center_lake_no_pose, "center block produced no pose against the lake",
                     { linus: 6, dijkstra: 8, maneuver: 16 }) ]
    end

    landed = actor.merge(x: plan[:pose][:x], y: plan[:pose][:y], facing: plan[:pose][:facing])
    if Sim::Geometry::Battlefield.rectangles_overlap?(landed, lake_obs)
      issues << issue(:center_lake_overlap, "center block overlapped the lake",
                      { linus: 8, dijkstra: 8, maneuver: 24 })
    end
    issues
  end

  def matchup_lakes
    [
      BattleScenarios.terrain(
        id: "lake-1", type: "lake", x: 16.584, y: 12.49, width: 4.207, depth: 3.997, impassable: true
      ),
      BattleScenarios.terrain(
        id: "lake-2", type: "lake", x: 25.078, y: 14.302, width: 3.98, depth: 2.848, impassable: true
      )
    ]
  end

  def to_h(report_obj = report)
    {
      linus: report_obj.linus,
      dijkstra: report_obj.dijkstra,
      maneuver: report_obj.maneuver,
      meets_bar: report_obj.meets_bar?,
      bar: BAR,
      issues: report_obj.issues.map { |entry| entry.slice(:id, :message, :file, :reviewers) }
    }
  end
end
