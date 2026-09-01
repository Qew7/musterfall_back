# frozen_string_literal: true

module Balance
  # Scans battle rule phase files for `# rule:` header comments.
  # Format: `# rule: <key> | <phase> | <concept>`
  module RuleCatalog
    RULES_ROOT = Rails.root.join("app/domain/sim/battle/rules")
    RULE_LINE = /^\s*#\s*rule:\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+)\z/

    module_function

    def scan
      entries = []
      Dir.glob(RULES_ROOT.join("**", "*.rb")).sort.each do |path|
        rel = Pathname.new(path).relative_path_from(RULES_ROOT).to_s
        concept_line = File.readlines(path, chomp: true).find { |line| line.match?(RULE_LINE) }
        next unless concept_line

        key, phase, concept = concept_line.match(RULE_LINE).captures
        entries << {
          path: rel,
          key: key.strip,
          phase: phase.strip,
          concept: concept.strip,
          raw: concept_line.sub(/\A#\s*/, "")
        }
      end
      entries
    end

    def by_key
      scan.group_by { |row| row[:key] }
    end

    def for_abilities(abilities)
      keys = Array(abilities).map { |ability| ability.to_s.underscore }
      by_key.slice(*keys)
    end

    def print_index(keys: nil)
      grouped = keys.present? ? for_abilities(keys) : by_key
      grouped.sort.each do |key, phases|
        puts "== #{key} =="
        phases.each do |row|
          puts "  #{row[:phase].ljust(10)} #{row[:concept]}"
        end
        puts
      end
    end
  end
end
