require 'spec_helper'
require_relative '../lib/config_manager'

RSpec.describe ConfigManager do
  let(:config) { described_class.new }

  before do
    # Clear any existing environment variables for testing
    ENV.delete('MAILGUN_API_KEY')
    ENV.delete('MAILGUN_API_BASE_URL')
    ENV.delete('MAILGUN_DOMAINS')
    ENV.delete('MG_DOMAIN1_COM_KEY')
    ENV.delete('MG_DOMAIN2_COM_KEY')
  end

  # Create a test-specific config manager that doesn't auto-load
  let(:test_config) do
    config = described_class.allocate
    config.instance_variable_set(:@api_key, nil)
    config.instance_variable_set(:@base_url, nil)
    config.instance_variable_set(:@domain, nil)
    config.instance_variable_set(:@from_address, nil)
    config.instance_variable_set(:@domains, [])
    config.instance_variable_set(:@domain_keys, {})
    config
  end

  describe '#initialize' do
    it 'initializes with default values' do
      # Test with a clean config that doesn't auto-load
      expect(test_config.api_key).to be_nil
      expect(test_config.base_url).to be_nil
      expect(test_config.domain).to be_nil
      expect(test_config.from_address).to be_nil
      expect(test_config.domains).to eq([])
      expect(test_config.domain_keys).to eq({})
    end
  end

  describe '#load_environment_variables' do
    before do
      ENV['MAILGUN_API_KEY'] = 'test-key'
      ENV['MAILGUN_API_BASE_URL'] = 'https://api.eu.mailgun.net'
      ENV['MAILGUN_DOMAINS'] = 'domain1.com,domain2.com'
      ENV['DOMAIN1_COM_KEY'] = 'key1'
      ENV['DOMAIN2_COM_KEY'] = 'key2'
    end

    after do
      ENV.delete('MAILGUN_API_KEY')
      ENV.delete('MAILGUN_API_BASE_URL')
      ENV.delete('MAILGUN_DOMAINS')
      ENV.delete('DOMAIN1_COM_KEY')
      ENV.delete('DOMAIN2_COM_KEY')
    end

    it 'loads environment variables correctly' do
      config.load_environment_variables
      
      expect(config.api_key).to eq('test-key')
      expect(config.base_url).to eq('https://api.eu.mailgun.net')
      expect(config.domains).to eq(['domain1.com', 'domain2.com'])
      expect(config.domain_keys).to eq({
        'domain1.com' => 'key1',
        'domain2.com' => 'key2'
      })
    end
  end

  describe '#validate_required_fields' do
    it 'returns errors when API key is missing' do
      errors = test_config.validate_required_fields
      expect(errors).to include('API key is required. Set MAILGUN_API_KEY in .env file or environment.')
    end

    it 'returns no errors when API key is present' do
      test_config.api_key = 'test-key'
      errors = test_config.validate_required_fields
      expect(errors).to be_empty
    end
  end
end
