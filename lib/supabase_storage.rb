# frozen_string_literal: true

require 'httparty'

class SupabaseStorage
  include HTTParty

  # SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY
  def initialize(base_url: ENV['SUPABASE_URL'], anon_key: ENV['SUPABASE_ANON_KEY'], service_key: ENV['SUPABASE_SERVICE_ROLE_KEY'])
    raise ArgumentError, 'SUPABASE_URL is required' if base_url.to_s.strip.empty?

    @base_url = base_url.chomp('/')
    @api_key = (service_key && !service_key.empty?) ? service_key : anon_key
    raise ArgumentError, 'Supabase key is required (SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY)' if @api_key.to_s.strip.empty?

    self.class.base_uri File.join(@base_url, '/storage/v1')
    self.class.headers(
      'apikey' => @api_key,
      'Authorization' => "Bearer #{@api_key}"
    )
  end

  # Uploads a local file to a bucket/path. Returns the public URL (assuming public bucket)
  def upload_object(bucket:, object_path:, file_path:, content_type: nil, upsert: true)
    raise ArgumentError, 'file not found' unless File.exist?(file_path)

    content_type ||= derive_content_type(file_path)
    body = File.binread(file_path)

    response = self.class.post(
      "/object/#{bucket}/#{object_path}",
      headers: {
        'Content-Type' => content_type,
        'x-upsert' => upsert ? 'true' : 'false'
      },
      body: body
    )

    handle_response(response)

    public_object_url(bucket:, object_path:)
  end

  def public_object_url(bucket:, object_path:)
    File.join(@base_url, "/storage/v1/object/public/#{bucket}/#{object_path}")
  end

  private

  def derive_content_type(file_path)
    case File.extname(file_path).downcase
    when '.png' then 'image/png'
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.gif' then 'image/gif'
    else 'application/octet-stream'
    end
  end

  def handle_response(response)
    code = response.code.to_i
    return true if code.between?(200, 299)

    begin
      body = response.body.to_s
      raise "Supabase Storage error (#{code}): #{body}"
    rescue StandardError
      raise "Supabase Storage error (#{code})"
    end
  end
end
