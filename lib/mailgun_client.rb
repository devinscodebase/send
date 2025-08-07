require 'httparty'
require 'json'
require 'digest'
require 'csv'
require 'parallel'

class MailgunClient
  include HTTParty

  def initialize(api_key, base_url = 'https://api.mailgun.net')
    @api_key = api_key
    @base_url = base_url
    @auth = { username: 'api', password: api_key }
  end

  # Fetch all domains available on the Mailgun account
  def list_domains
    response = HTTParty.get(
      "#{@base_url}/v4/domains",
      basic_auth: @auth,
      headers: { 'Content-Type' => 'application/json' }
    )

    handle_response(response) do |body|
      body['items'] || []
    end
  end

  # Create a new mailing list
  def create_mailing_list(address, name = nil, description = nil)
    body = { address: address }
    body[:name] = name if name
    body[:description] = description if description

    response = HTTParty.post(
      "#{@base_url}/v3/lists",
      basic_auth: @auth,
      body: body
    )

    handle_response(response) do |body|
      {
        id: body['list']['id'],
        address: body['list']['address'],
        name: body['list']['name']
      }
    end
  end

  # Upload contacts from CSV to a mailing list
  def upload_mailing_list_members(list_address, csv_file_path)
    response = HTTParty.post(
      "#{@base_url}/v3/lists/#{list_address}/members.csv",
      basic_auth: @auth,
      body: {
        subscribed: true,
        upsert: true,
        members: File.new(csv_file_path)
      }
    )

    handle_response(response) do |body|
      {
        message: body['message'],
        task_id: body['task_id']
      }
    end
  end

  # Send email to a mailing list
  def send_message(domain, from_address, to_address, subject, html_content, options = {})
    body = {
      from: from_address,
      to: to_address,
      subject: subject,
      html: html_content
    }

    # Add optional parameters
    body['o:deliverytime'] = options[:delivery_time] if options[:delivery_time]
    body['o:testmode'] = 'yes' if options[:test_mode]
    body['o:tracking'] = options[:tracking] if options[:tracking]
    body['o:tag'] = options[:tag] if options[:tag]

    # Use domain-specific auth if provided
    auth = options[:domain_key] ? { username: 'api', password: options[:domain_key] } : @auth

    response = HTTParty.post(
      "#{@base_url}/v3/#{domain}/messages",
      basic_auth: auth,
      body: body
    )

    handle_response(response) do |body|
      {
        id: body['id'],
        message: body['message']
      }
    end
  end

  # Send email to individual recipients
  def send_bulk_emails(domain, from_address, recipients, subject, html_content, options = {})
    # Rate limiting configuration
    max_threads = options[:max_threads] || 5
    delay_between_requests = options[:delay_between_requests] || 0.1
    # Debug: Check if domain key is being passed
    if options[:domain_key]
      puts "🔑 Using domain key: #{options[:domain_key][0..10]}..."
    else
      puts '⚠️  No domain key provided'
    end

    # Extract sender info from from_address
    sender_info = extract_sender_info(from_address)

    # Determine number of threads (conservative to respect rate limits)
    # Mailgun typically allows 10-20 requests per second, so we'll use 5 threads max
    thread_count = [Parallel.processor_count, max_threads].min
    puts "🚀 Using #{thread_count} parallel threads for sending (respecting rate limits)..."

    # Process recipients in parallel with rate limiting
    parallel_results = Parallel.map(recipients, in_threads: thread_count) do |recipient|
      # Add a small delay to respect rate limits
      sleep(delay_between_requests) if thread_count > 1

      # Personalize the HTML content for this recipient
      personalized_html = personalize_html(html_content, recipient, sender_info)

      # Send to individual recipient
      result = send_message(domain, from_address, recipient[:email], subject, personalized_html, options)
      puts "✅ Sent to: #{recipient[:email]}"
      { email: recipient[:email], success: true, message_id: result[:id] }
    rescue MailgunError => e
      if e.message.include?('Rate limit exceeded')
        puts "⚠️  Rate limit hit for #{recipient[:email]} - will retry..."
        # Wait longer for rate limit errors
        sleep(1.0)
        # Retry once
        begin
          result = send_message(domain, from_address, recipient[:email], subject, personalized_html, options)
          puts "✅ Sent to: #{recipient[:email]} (retry successful)"
          { email: recipient[:email], success: true, message_id: result[:id] }
        rescue MailgunError => retry_error
          puts "❌ Failed to send to: #{recipient[:email]} - #{retry_error.message}"
          { email: recipient[:email], success: false, error: retry_error.message }
        end
      else
        puts "❌ Failed to send to: #{recipient[:email]} - #{e.message}"
        { email: recipient[:email], success: false, error: e.message }
      end
    end

    # Collect results
    parallel_results.map { |result| result }
  end

  private

  def extract_sender_info(from_address)
    # Parse "Grant Walker <grant@mg.pensionaid.org>" format
    if from_address =~ /(.+?)\s*<(.+?)>/
      name = ::Regexp.last_match(1).strip
      email = ::Regexp.last_match(2).strip
    else
      name = 'Grant Walker'
      email = from_address
    end

    # Load profile picture - try Imgur URL first, fallback to Gravatar
    profile_picture = ''
    begin
      # Try to load from Imgur URL file
      imgur_url = File.read('profiles/grant-walker-imgur-url.txt').strip
      profile_picture = imgur_url if imgur_url.start_with?('http')
    rescue StandardError
      # If no Imgur URL, use Gravatar for the email
      email_hash = Digest::MD5.hexdigest(email.downcase.strip)
      profile_picture = "https://www.gravatar.com/avatar/#{email_hash}?s=100&d=mp"
    end

    {
      name: name,
      email: email.gsub('mg.', ''), # Remove 'mg.' from email for signature
      title: 'Retirement Advisor',
      profile_picture: profile_picture
    }
  end

  def personalize_html(html_content, recipient, sender_info = {})
    personalized = html_content.dup

    # Replace recipient personalization variables
    first_name = recipient[:firstname] || recipient[:name]&.split&.first || 'there'
    full_name = [recipient[:firstname], recipient[:lastname]].compact.join(' ')
    full_name = full_name.empty? ? (recipient[:name] || 'there') : full_name
    company = recipient[:company] || 'your company'

    personalized.gsub!('%recipient.first%', first_name)
    personalized.gsub!('%recipient.name%', full_name)
    personalized.gsub!('%recipient.company%', company)

    # Replace sender personalization variables
    personalized.gsub!('%sender.name%', sender_info[:name] || 'Grant Walker')
    personalized.gsub!('%sender.title%', sender_info[:title] || 'Retirement Advisor')
    personalized.gsub!('%sender.email%', sender_info[:email] || 'grant@mg.pensionaid.org')
    personalized.gsub!('%sender.profile_picture%', sender_info[:profile_picture] || '')

    personalized
  end

  # Get mailing list members count
  def get_mailing_list_members_count(list_address)
    response = HTTParty.get(
      "#{@base_url}/v3/lists/#{list_address}/members",
      basic_auth: @auth,
      query: { limit: 1 }
    )

    handle_response(response) do |body|
      body['total_count'] || 0
    end
  end

  def handle_response(response)
    case response.code
    when 200, 201
      yield JSON.parse(response.body)
    when 401
      raise MailgunError, 'Authentication failed. Please check your API key.'
    when 400
      error_body = JSON.parse(response.body)
      raise MailgunError, "Bad request: #{error_body['message'] || 'Invalid parameters'}"
    when 429
      raise MailgunError, 'Rate limit exceeded. Please wait before retrying.'
    when 500..599
      raise MailgunError, 'Mailgun server error. Please try again later.'
    else
      raise MailgunError, "Unexpected response: #{response.code} - #{response.body}"
    end
  rescue JSON::ParserError
    raise MailgunError, 'Invalid JSON response from Mailgun'
  end
end

class MailgunError < StandardError; end
