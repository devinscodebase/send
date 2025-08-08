# frozen_string_literal: true

require 'httparty'
require 'json'
require 'dotenv/load'

class SupabaseClient
  include HTTParty

  def initialize(base_url: ENV.fetch('SUPABASE_URL', nil),
                 anon_key: ENV.fetch('SUPABASE_ANON_KEY', nil),
                 service_key: ENV.fetch('SUPABASE_SERVICE_ROLE_KEY', nil),
                 publishable_key: ENV.fetch('SUPABASE_PUBLISHABLE_KEY', nil),
                 secret_key: ENV.fetch('SUPABASE_SECRET_KEY', nil))
    raise ArgumentError, 'SUPABASE_URL is required' if base_url.to_s.strip.empty?

    @base_url = base_url.chomp('/')

    # Prefer new naming if provided, otherwise fall back to legacy
    @publishable = publishable_key.to_s.strip.empty? ? anon_key : publishable_key
    @secret      = secret_key.to_s.strip.empty? ? service_key : secret_key

    if @publishable.to_s.strip.empty? && @secret.to_s.strip.empty?
      raise ArgumentError, 'Supabase key is required (publishable/anon or secret/service_role)'
    end

    self.class.base_uri File.join(@base_url, '/rest/v1')

    # Build headers
    headers = {
      'apikey' => (@publishable.to_s.strip.empty? ? @secret : @publishable),
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'Accept-Encoding' => 'identity',
      'Accept-Profile' => 'public',
      'Content-Profile' => 'public'
    }

    # Authorization only if the token is a JWT (eyJ... with two dots)
    auth_token = @secret.to_s.strip.empty? ? @publishable : @secret
    if jwt_like?(auth_token)
      headers['Authorization'] = "Bearer #{auth_token}"
    end

    self.class.headers(headers)
    # Also provide apikey as a query param (helps in some environments)
    self.class.default_params apikey: (@publishable.to_s.strip.empty? ? @secret : @publishable)
  end

  def upsert_sender(sender)
    validate_sender!(sender)

    query = { on_conflict: 'email_address,domain_name' }
    response = self.class.post(
      '/senders',
      query: query,
      headers: { 'Prefer' => 'resolution=merge-duplicates,return=representation' },
      body: sender.to_json
    )
    debug_log(response)
    handle_response(response)
  end

  def update_sender_profile_picture(email_address, domain_name, profile_picture_url)
    response = self.class.patch(
      '/senders',
      query: {
        email_address: "eq.#{email_address}",
        domain_name: "eq.#{domain_name}"
      },
      headers: { 'Prefer' => 'return=representation' },
      body: { profile_picture_url: profile_picture_url }.to_json
    )
    debug_log(response)
    handle_response(response)
  end

  def get_sender(email_address, domain_name)
    response = self.class.get(
      '/senders',
      query: {
        select: '*',
        email_address: "eq.#{email_address}",
        domain_name: "eq.#{domain_name}",
        limit: 1
      }
    )
    debug_log(response)
    data = handle_response(response)
    data.is_a?(Array) ? data.first : data
  end

  def list_senders(domain_name: nil, focus: nil, limit: 100)
    query = { select: '*', limit: limit }
    query[:domain_name] = "eq.#{domain_name}" if domain_name
    if focus && !focus.to_s.strip.empty?
      query[:focus] = "eq.#{focus}"
    end

    response = self.class.get('/senders', query: query)
    debug_log(response)
    handle_response(response)
  end

  private

  def validate_sender!(sender)
    required = %i[first_name last_name email_address domain_name profile_picture_url]
    missing = required.reject { |k| !sender[k].nil? && !(sender[k].respond_to?(:empty?) && sender[k].empty?) }
    raise ArgumentError, "Missing required fields: #{missing.join(', ')}" unless missing.empty?
  end

  def jwt_like?(token)
    t = token.to_s
    t.start_with?('eyJ') && t.count('.') == 2
  end

  def handle_response(response)
    code = response.code.to_i
    if code.between?(200, 299)
      body = response.body.to_s
      return [] if body.strip.empty?

      begin
        return JSON.parse(body)
      rescue JSON::ParserError
        return []
      end
    end

    message = begin
      parsed = JSON.parse(response.body)
      parsed['message'] || parsed['error'] || response.body
    rescue StandardError
      response.body
    end
    raise "Supabase error (#{code}): #{message}"
  end

  def debug_log(response)
    return unless ENV['DEBUG_SUPABASE']

    puts "[Supabase] #{response.request.http_method::METHOD} #{response.request.last_uri}"
    snippet = response.body.to_s[0, 300]
    puts "[Supabase] Status: #{response.code} Body bytes: #{response.body.to_s.bytesize}"
    puts "[Supabase] Body (first 300 chars): #{snippet}"
  end
end
