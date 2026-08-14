#!/usr/bin/env ruby

require "optparse"
require "yaml"

options = {
  required_users: 10,
  allow_shared_data: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: validate_test_folder.rb --folder PATH [options]"
  parser.on("--folder PATH", "Local folder containing the three staged YAML files") { |value| options[:folder] = value }
  parser.on("--required-users N", Integer, "Required virtual-user capacity (default: 10)") { |value| options[:required_users] = value }
  parser.on("--allow-shared-data", "Allow a complete dataset to be reused by multiple virtual users") { options[:allow_shared_data] = true }
end.parse!

def fail_validation(message)
  warn "TEN_USER_DATA_GATE=FAIL reason=#{message}"
  exit 1
end

def load_yaml(path)
  content = File.binread(path)
  YAML.safe_load(
    content,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: true,
    filename: path
  )
rescue Psych::Exception => e
  fail_validation("invalid_yaml file=#{File.basename(path)} detail=#{e.message.lines.first.to_s.strip}")
end

def integer_value(value)
  Integer(value)
rescue ArgumentError, TypeError
  nil
end

folder = options[:folder]
fail_validation("missing_folder_argument") if folder.nil? || folder.strip.empty?
fail_validation("folder_not_found") unless File.directory?(folder)
fail_validation("invalid_required_users") unless options[:required_users].is_a?(Integer) && options[:required_users] > 0

paths = {
  "config.yaml" => File.join(folder, "config.yaml"),
  "scenario.yaml" => File.join(folder, "scenario.yaml"),
  "scenario-data.yaml" => File.join(folder, "scenario-data.yaml")
}

paths.each do |name, path|
  fail_validation("missing_or_unreadable file=#{name}") unless File.file?(path) && File.readable?(path)
end

config = load_yaml(paths.fetch("config.yaml"))
scenario = load_yaml(paths.fetch("scenario.yaml"))
scenario_data = load_yaml(paths.fetch("scenario-data.yaml"))

fail_validation("config_root_not_mapping") unless config.is_a?(Hash)
fail_validation("scenario_root_not_mapping") unless scenario.is_a?(Hash)
fail_validation("scenario_data_root_not_mapping") unless scenario_data.is_a?(Hash)

expected_scenario = {
  "startUsers" => 1,
  "endUsers" => 10,
  "durationSeconds" => 600,
  "rampDurationSeconds" => 0
}

expected_scenario.each do |key, expected|
  actual = integer_value(scenario[key])
  fail_validation("scenario_value key=#{key} expected=#{expected} actual=#{scenario[key].inspect}") unless actual == expected
end

config_authority = config["authority"].to_s.strip
fail_validation("config_authority expected=ablfeda") unless config_authority.casecmp("ablfeda").zero?

global_sets = scenario_data["globalDataSets"]
fail_validation("globalDataSets_missing_or_empty") unless global_sets.is_a?(Array) && !global_sets.empty?

placeholder_pattern = /(?:\bChange_Me\b|\bREPLACE_ME\b|<\s*(?:TODO|REQUIRED|VALUE)\s*>)/i
identity_name_pattern = /(?:username|user_id|prsnl_id|personnel_id)/i
identity_param_count = 0

global_sets.each_with_index do |data_set, index|
  fail_validation("dataset_not_mapping index=#{index}") unless data_set.is_a?(Hash)
  params = data_set["params"]
  fail_validation("dataset_params_missing index=#{index}") unless params.is_a?(Array) && !params.empty?

  param_map = {}
  params.each do |param|
    fail_validation("dataset_param_not_mapping index=#{index}") unless param.is_a?(Hash)
    name = param["name"].to_s.strip
    value = param["value"]
    fail_validation("dataset_param_name_missing index=#{index}") if name.empty?
    fail_validation("dataset_param_duplicate index=#{index} name=#{name}") if param_map.key?(name)
    param_map[name] = value

    scalar = value.nil? ? "" : value.to_s.strip
    if scalar.match?(placeholder_pattern)
      fail_validation("unresolved_placeholder dataset=#{index} name=#{name}")
    end
    if name.match?(identity_name_pattern)
      identity_param_count += 1
      fail_validation("identity_value_missing dataset=#{index} name=#{name}") if scalar.empty?
    end
  end

  authority_entry = param_map.find { |name, _value| name.casecmp("authority").zero? }
  fail_validation("scenario_data_authority_missing dataset=#{index}") if authority_entry.nil?
  authority_value = authority_entry[1].to_s.strip
  fail_validation("scenario_data_authority expected=ablfeda dataset=#{index}") unless authority_value.casecmp("ablfeda").zero?
end

fail_validation("identity_parameters_missing") if identity_param_count.zero?

data_mode = if global_sets.length >= options[:required_users]
              "dedicated"
            elsif options[:allow_shared_data]
              "shared-approved"
            else
              fail_validation("insufficient_datasets count=#{global_sets.length} required=#{options[:required_users]} shared_reuse_not_approved")
            end

puts "TEN_USER_DATA_GATE=PASS mode=#{data_mode} dataset_count=#{global_sets.length} required_users=#{options[:required_users]} identity_params=#{identity_param_count}"
