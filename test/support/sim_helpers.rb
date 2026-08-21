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
    faction = catalog.factions.first
    Games::ApplyCommand.call(
      game: game,
      command: :assign_faction,
      base_version: game.campaign_version,
      params: { player_id: player_id, faction_id: faction[:id], school_key: starter_school_key(faction[:id]) }
    ).tap { |result| raise result.error unless result.ok? }
  end

  def starter_school_key(faction_id)
    hero = catalog.hero_templates(faction_id).first
    Sim::Battle::Spells.schools_for(faction_id).first if hero&.dig(:abilities)&.include?("wizard")
  end

  def with_spell_api(schools:, spell_keys:, school: { name: "Test school", spells: [] })
    singleton = Sim::Battle::Spells.singleton_class
    replacements = { schools_for: schools, spell_keys: spell_keys, school: school }
    originals = replacements.keys.to_h do |name|
      [ name, singleton.method_defined?(name) ? singleton.instance_method(name) : nil ]
    end
    replacements.each { |name, value| singleton.define_method(name) { |*| value } }
    yield
  ensure
    originals&.each do |name, method|
      method ? singleton.define_method(name, method) : singleton.remove_method(name)
    end
  end
end
