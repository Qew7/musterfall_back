class CatalogVersion < ApplicationRecord
  has_many :balance_battle_rollups, dependent: :destroy
  has_many :balance_counters, dependent: :destroy

  validates :content_hash, :catalog_hash, :rules_hash, presence: true
  validates :content_hash, uniqueness: true

  def self.current!
    catalog_hash = Balance::CatalogFingerprint.catalog_hash
    rules_hash = Balance::CatalogFingerprint.rules_hash
    content_hash = Digest::SHA256.hexdigest("#{catalog_hash}:#{rules_hash}")

    find_or_create_by!(content_hash: content_hash) do |version|
      version.catalog_hash = catalog_hash
      version.rules_hash = rules_hash
    end
  end
end
