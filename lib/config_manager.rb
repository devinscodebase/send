require 'yaml'
require 'json'
require 'dotenv'

class ConfigManager
  attr_accessor :domain, :from_address, :list_name, :api_key, :base_url, :domains, :domain_keys

  def initialize
    load_environment_variables
    load_config_file
  end

  def load_environment_variables
    Dotenv.load('.env') if File.exist?('.env')
    Dotenv.load('domains.env') if File.exist?('domains.env')

    @api_key = ENV.fetch('MAILGUN_API_KEY', nil)
    @base_url = ENV['MAILGUN_API_BASE_URL'] || 'https://api.mailgun.net'
    @domains = ENV['MAILGUN_DOMAINS']&.split(',') || []
    @domain_keys = load_domain_keys
  end

  def load_config_file
    config_file = find_config_file
    return unless config_file

    config = case File.extname(config_file)
             when '.yml', '.yaml'
               YAML.load_file(config_file)
             when '.json'
               JSON.parse(File.read(config_file))
             end

    return unless config

    @domain = config['default_domain'] || config[:default_domain]
    @from_address = config['default_from'] || config[:default_from]
    @list_name = config['default_list_name'] || config[:default_list_name]
  end

  def find_config_file
    %w[config.yml config.yaml config.json .mailgun_config.yml .mailgun_config.yaml .mailgun_config.json].find do |file|
      File.exist?(file)
    end
  end

  def validate_required_fields
    errors = []
    errors << 'API key is required. Set MAILGUN_API_KEY in .env file or environment.' unless @api_key
    errors
  end

  def to_s
    "Config: domain=#{@domain}, from=#{@from_address}, list=#{@list_name}, base_url=#{@base_url}, domains=#{@domains.length}"
  end

  private

  def load_domain_keys
    keys = {}
    @domains.each do |domain|
      # Convert domain to environment variable name
      env_var = "#{domain.gsub(/[.-]/, '_').upcase}_KEY"
      key = ENV.fetch(env_var, nil)
      keys[domain] = key if key
    end
    keys
  end
end
