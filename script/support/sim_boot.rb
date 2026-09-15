require "active_support/all"
require "zeitwerk"
require "json"

# The same domain autoloading for profiling and database-free tests. Rails owns
# its loader when this helper is loaded by the integration suite.
module SimTools
  ROOT = File.expand_path("../..", __dir__)

  unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application
    LOADER = Zeitwerk::Loader.new
    LOADER.push_dir(File.join(ROOT, "app/domain"))
    LOADER.setup
  end

  def self.catalog
    # Corpus armies contain their combat profiles. The catalog is only used for
    # faction presentation in these replays, not combat rules.
    Sim::Catalog.new(
      formation_rules: { max_files: 5 }, model_classes: [], factions: [],
      units: [], heroes: [], abilities: [], hero_upgrades: []
    )
  end
end
