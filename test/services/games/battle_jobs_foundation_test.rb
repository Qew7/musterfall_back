require "test_helper"

class GamesBattleJobsFoundationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "advance_round persists matchups and completes via battle jobs" do
    game = create_active_game(player_count: 2)

    assert_equal :inline, Rails.configuration.x.battle_jobs.execution_mode

    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error

    game.reload
    matchups = game.round_matchups.order(:position)
    assert_equal 1, matchups.size
    assert matchups.all?(&:completed?)
    assert matchups.first.seed.present?
    assert game.battles.any?
  end

  test "advance_round async enqueues jobs and settle_round completes round" do
    previous_mode = Rails.configuration.x.battle_jobs.execution_mode
    previous_adapter = ActiveJob::Base.queue_adapter
    Rails.configuration.x.battle_jobs.execution_mode = :async
    ActiveJob::Base.queue_adapter = :test

    game = create_active_game(player_count: 2)

    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?, result.error
    assert result.value[:pending]

    game.reload
    assert_equal "simulating", game.status

    perform_enqueued_jobs
    perform_enqueued_jobs

    game.reload
    assert_equal "active", game.status
    assert game.battles.any?
    assert game.round_matchups.all?(&:completed?)
  ensure
    Rails.configuration.x.battle_jobs.execution_mode = previous_mode
    ActiveJob::Base.queue_adapter = previous_adapter
    clear_enqueued_jobs
  end

  test "plan_matchups assigns distinct seeds per pair" do
    campaign = Sim::Campaign::Create.call(player_count: 4).value
    prepared = Sim::Campaign::PrepareRound.call(
      campaign: campaign,
      catalog: catalog,
      rng: Sim::Rng::Seeded.new(11)
    ).value

    planned = Sim::Campaign::PlanMatchups.call(
      campaign: prepared,
      catalog: catalog,
      rng_seed: 42
    )

    assert planned.ok?
    matchups = planned.value[:matchups]
    assert_equal 2, matchups.size
    assert_equal matchups.map { |entry| entry[:seed] }.uniq.size, matchups.size
  end

  test "simulate battle job is idempotent when already completed" do
    game = create_active_game(player_count: 2)
    result = Games::AdvanceRound.call(game: game, base_version: 0)
    assert result.ok?

    matchup = game.round_matchups.first
    assert matchup.completed?
    payload = matchup.result_payload.deep_dup

    SimulateBattleJob.perform_now(matchup.id)
    matchup.reload
    assert_equal payload, matchup.result_payload
  end
end
