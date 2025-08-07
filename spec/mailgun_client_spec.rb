require 'spec_helper'
require_relative '../lib/mailgun_client'

RSpec.describe MailgunClient do
  let(:api_key) { 'test-api-key' }
  let(:base_url) { 'https://api.mailgun.net' }
  let(:client) { described_class.new(api_key, base_url) }

  describe '#initialize' do
    it 'sets the API key and base URL' do
      expect(client.instance_variable_get(:@api_key)).to eq(api_key)
      expect(client.instance_variable_get(:@base_url)).to eq(base_url)
    end

    it 'sets up authentication' do
      auth = client.instance_variable_get(:@auth)
      expect(auth[:username]).to eq('api')
      expect(auth[:password]).to eq(api_key)
    end
  end

  describe '#list_domains' do
    it 'makes a GET request to the domains endpoint' do
      mock_response = double('response', code: 200, body: '{"items": []}')
      expect(HTTParty).to receive(:get).with(
        "#{base_url}/v4/domains",
        basic_auth: { username: 'api', password: api_key },
        headers: { 'Content-Type' => 'application/json' }
      ).and_return(mock_response)

      result = client.list_domains
      expect(result).to eq([])
    end
  end

  describe '#create_mailing_list' do
    it 'makes a POST request to create a mailing list' do
      address = 'test@example.com'
      name = 'Test List'
      description = 'Test description'
      mock_response = double('response', code: 200, body: '{"message": "Mailing list created", "list": {"id": "test-list-id"}}')

      expect(HTTParty).to receive(:post).with(
        "#{base_url}/v3/lists",
        basic_auth: { username: 'api', password: api_key },
        body: {
          address: address,
          name: name,
          description: description
        }
      ).and_return(mock_response)

      result = client.create_mailing_list(address, name, description)
      expect(result[:id]).to eq('test-list-id')
    end
  end

  describe '#send_message' do
    it 'makes a POST request to send a message' do
      domain = 'example.com'
      from_address = 'sender@example.com'
      to_address = 'list@example.com'
      subject = 'Test Subject'
      html_content = '<html>Test</html>'
      options = { test_mode: true }
      mock_response = double('response', code: 200, body: '{"id": "test-message-id"}')

      expect(HTTParty).to receive(:post).with(
        "#{base_url}/v3/#{domain}/messages",
        basic_auth: { username: 'api', password: api_key },
        body: {
          from: from_address,
          to: to_address,
          subject: subject,
          html: html_content,
          'o:testmode' => 'yes'
        }
      ).and_return(mock_response)

      result = client.send_message(domain, from_address, to_address, subject, html_content, options)
      expect(result[:id]).to eq('test-message-id')
    end
  end
end
