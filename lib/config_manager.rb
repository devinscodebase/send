require 'yaml'
require 'json'
require 'dotenv'

class ConfigManager
  attr_accessor :api_key

  def initialize
    load_environment_variables
  end

  def load_environment_variables
    Dotenv.load('.env') if File.exist?('.env')
    keys_str = ENV['RESEND_API_KEYS'] || ENV.fetch('RESEND_API_KEY', nil)
    @api_key = keys_str ? keys_str.split(',').map(&:strip).first : nil
  end

  def validate_required_fields
    errors = []
    errors << 'API key is required. Set RESEND_API_KEY in your .env file.' if @api_key.nil? || @api_key.empty?
    errors
  end

  def to_s
    'Config: API Key Loaded'
  end
end
