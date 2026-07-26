module SimHelpers
  def catalog
    @catalog ||= Sim::Catalog::Loader.load
  end

  def create_active_game(player_count: 2)
    result = Games::CreateGame.call(player_count: player_count)
    raise result.error unless result.ok?

    result.value
  end

  def assign_first_faction!(game, player_id: "player-1")
    Games::ApplyCommand.call(
      game: game,
      command: :assign_faction,
      base_version: game.campaign_version,
      params: { player_id: player_id, faction_id: catalog.factions.first[:id] }
    ).tap { |result| raise result.error unless result.ok? }
  end
end
