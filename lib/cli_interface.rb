require 'optparse'
require 'tempfile'
require 'csv'
require 'uri'
require 'securerandom'
require_relative 'resend_client'
require_relative 'config_manager'
require_relative 'csv_validator'
require_relative 'supabase_client'

class CliInterface
  BATCH_SIZE = 100 # Resend's maximum batch size
  BATCH_DELAY = 0.6 # Delay between sending batches to stay under 2 RPS

  attr_reader :config, :client, :options

  def initialize
    @config = ConfigManager.new
    @options = {}
    setup_option_parser
  end

  def run
    parse_arguments
    validate_configuration
    setup_resend_client
    execute_workflow
  rescue Interrupt
    puts "\nOperation cancelled by user."
    exit 1
  rescue StandardError => e
    puts "Error: #{e.message}"
    exit 1
  end

  private

  def setup_option_parser
    @option_parser = OptionParser.new do |opts|
      opts.banner = 'Usage: resend_sender [options]'
      opts.separator ''
      opts.separator 'Core Options:'
      opts.on('--csv=FILE', 'Path to contacts CSV file (required)') { |v| @options[:csv_file] = v }
      opts.on('--template=FILE', 'Path to HTML template file (required)') { |v| @options[:template_file] = v }
      opts.on('--subject=TEXT',
              '(Optional) Email subject line template. Defaults to loading from <template_name>_subject.txt') do |v|
        @options[:subject] = v
      end
      opts.separator ''
      opts.separator 'Sender Selection:'
      opts.on('--focus=TEXT', 'Select sender by focus (e.g., "Higher Education")') { |v| @options[:focus] = v }
      opts.on('--sender-email=EMAIL', 'Select sender by email (requires --focus)') { |v| @options[:sender_email] = v }
      opts.separator ''
      opts.separator 'Sending Options:'
      opts.on('--yes', 'Auto-confirm send without prompt') { @options[:yes] = true }
      opts.on('--dry-run', 'Show summary and exit without sending') { @options[:dry_run] = true }
      opts.separator ''
      opts.separator 'General Options:'
      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit
      end
      opts.on('--version', 'Show version') do
        puts 'Resend CLI Sender v1.5.0 (Campaign UUID Mode)'
        exit
      end
    end
  end

  def parse_arguments
    @option_parser.parse!(into: @options)
    unless @options[:csv_file] && @options[:template_file]
      puts 'Error: --csv and --template are required.'
      puts @option_parser
      exit 1
    end
  end

  def validate_configuration
    errors = @config.validate_required_fields
    unless errors.empty?
      puts "Configuration Error: #{errors.join(', ')}"
      exit 1
    end
  end

  def setup_resend_client
    @client = ResendClient.new(@config.api_key)
  end

  def execute_workflow
    puts '🚀 Resend CLI Bulk Email Sender (Campaign UUID Mode)'
    puts '=' * 50

    campaign_id = SecureRandom.uuid
    sender = select_sender_via_supabase
    from_address = "#{sender['first_name']} #{sender['last_name']} <#{sender['email_address']}>"
    subject_template = load_subject_line

    puts "\n📋 Validating CSV file..."
    csv_validator = CsvValidator.new(@options[:csv_file])
    csv_validator.validate_and_parse
    puts "✅ Found #{csv_validator.valid_contact_count} valid contacts."

    puts "\n📄 Loading email template..."
    html_content = File.read(@options[:template_file])
    puts '✅ Template loaded.'

    show_summary(from_address, sender['domain_name'], csv_validator.valid_contact_count, subject_template, campaign_id)
    exit 0 if @options[:dry_run]
    unless confirm_operation
      puts 'Operation cancelled.'
      exit 0
    end

    perform_batch_send(from_address, csv_validator.contacts, subject_template, html_content, sender, campaign_id)

    puts "\n🏷️ Campaign UUID for tracking: #{campaign_id}"
  end

  def load_subject_line
    return @options[:subject] if @options[:subject]

    template_path = @options[:template_file]
    subject_path = template_path.gsub(/\.html$/, '_subject.txt')
    unless File.exist?(subject_path)
      raise "Error: Subject not provided and default subject file not found at '#{subject_path}'"
    end

    puts "✅ Loaded subject template from '#{subject_path}'"
    File.read(subject_path).strip
  end

  def select_sender_via_supabase
    sb = SupabaseClient.new
    focuses = ['Higher Education', 'School Districts', 'Federal Government', 'Internal Marketing', 'Client Marketing']
    if @options[:focus]
      focus = @options[:focus]
      senders = sb.list_senders(focus: focus)
    else
      puts "\nFocus? Choose one:"
      focuses.each_with_index { |f, i| puts "  #{i + 1}) #{f}" }
      print 'Enter 1-5: '
      choice = STDIN.gets.to_i
      focus = focuses[choice - 1]
      raise 'Invalid choice.' unless focus

      senders = sb.list_senders(focus: focus)
    end
    if senders.empty?
      puts "No senders found for focus '#{focus}'. Fetching all senders as a fallback..."
      senders = sb.list_senders
      raise 'No senders found in Supabase at all.' if senders.empty?
    end
    if @options[:sender_email]
      sender = senders.find { |s| s['email_address'].casecmp?(@options[:sender_email]) }
      raise "Sender with email '#{@options[:sender_email]}' not found for the selected focus." unless sender
    else
      puts "\nAvailable senders:"
      senders.each_with_index do |s, i|
        puts "  [#{i + 1}] #{s['first_name']} #{s['last_name']} <#{s['email_address']}>"
      end
      print "Select sender (1-#{senders.length}): "
      choice = STDIN.gets.to_i
      sender = senders[choice - 1]
      raise 'Invalid selection.' unless sender
    end
    puts "✅ Selected sender: #{sender['first_name']} #{sender['last_name']}"
    sender
  end

  def show_summary(from_address, domain, recipient_count, subject_template, campaign_id)
    puts "\n#{'=' * 50}"
    puts '📧 EMAIL SEND SUMMARY'
    puts '=' * 50
    puts "From: #{from_address}"
    puts "Domain: #{domain}"
    puts "Recipients: #{recipient_count}"
    puts "Subject Template: #{subject_template}"
    puts "Campaign ID: #{campaign_id}"
    puts "Dry Run: #{@options[:dry_run] ? 'Yes' : 'No'}"
    puts '=' * 50
  end

  def confirm_operation
    return true if @options[:yes]

    print "\nProceed with sending? (y/N): "
    STDIN.gets.strip.casecmp?('y')
  end

  def personalize_text(text, recipient)
    return text unless text.include?('%')

    personalized = text.dup
    personalized.gsub!('%recipient.first%', recipient[:firstname] || '')
    personalized.gsub!('%recipient.last%', recipient[:lastname] || '')
    personalized.gsub!('%recipient.name%', "#{recipient[:firstname]} #{recipient[:lastname]}".strip)
    personalized.gsub!('%recipient.company%', recipient[:company] || '')
    personalized.gsub!('%recipient.email%', recipient[:email] || '')
    personalized
  end

  def personalize_html(html_content, recipient, sender, template_name, campaign_id)
    personalized = personalize_text(html_content, recipient)
    personalized.gsub!('%sender.name%', "#{sender['first_name']} #{sender['last_name']}")
    personalized.gsub!('%sender.title%', 'Financial Advisor')
    personalized.gsub!('%sender.email%', sender['email_address'])
    personalized.gsub!('%sender.profile_picture%', sender['profile_picture_url'])
    update_calendly_link(personalized, template_name, campaign_id)
    personalized
  end

  def update_calendly_link(html_content, template_name, campaign_id)
    html_content.gsub!(%r{(https://calendly\.com/[^\s"']+)}) do |match|
      uri = URI.parse(match)
      params = URI.decode_www_form(uri.query || '').to_h
      params['utm_source'] = 'RS'
      params['utm_content'] = template_name.gsub(/\.html$/, '')
      params['utm_campaign'] = campaign_id
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end
  end

  def write_results_to_csv(results)
    sent_path = 'sent.csv'
    failed_path = 'failed_to_send.csv'

    CSV.open(sent_path, 'w') do |csv|
      csv << ['email']
      results.select { |r| r[:success] }.each { |r| csv << [r[:email]] }
    end

    CSV.open(failed_path, 'w') do |csv|
      csv << %w[email error]
      results.reject { |r| r[:success] }.each { |r| csv << [r[:email], r[:error]] }
    end

    puts "\n💾 Results saved:"
    puts "   - Sent log: #{sent_path}"
    puts "   - Failed log: #{failed_path}"
  end

  def perform_batch_send(from_address, contacts, subject_template, html_template, sender, campaign_id)
    puts "\n📤 Preparing emails for batch sending..."
    template_name = File.basename(@options[:template_file])
    valid_contacts = contacts.select { |c| c[:valid] }
    all_results = []

    email_payloads = valid_contacts.map do |contact|
      {
        from: from_address,
        to: contact[:email],
        subject: personalize_text(subject_template, contact),
        html: personalize_html(html_template, contact, sender, template_name, campaign_id)
      }
    end

    total_emails = email_payloads.length
    total_batches = (total_emails / BATCH_SIZE.to_f).ceil

    email_payloads.each_slice(BATCH_SIZE).with_index do |batch, index|
      puts "📦 Sending batch #{index + 1} of #{total_batches} (#{batch.length} emails)..."
      begin
        response = @client.send_batch(batch)
        if response && response[:data]
          puts "✅ Batch #{index + 1} accepted by API. #{response[:data].length} emails created."
          batch.each { |payload| all_results << { email: payload[:to], success: true } }
        else
          puts "❌ Batch #{index + 1} failed: Unexpected API response."
          batch.each do |payload|
            all_results << { email: payload[:to], success: false, error: 'Unexpected API response' }
          end
        end
      rescue ResendClient::ResendError => e
        puts "❌ Batch #{index + 1} failed: #{e.message}"
        batch.each { |payload| all_results << { email: payload[:to], success: false, error: e.message } }
      end
      sleep(BATCH_DELAY) if index < total_batches - 1
    end

    successful_sends = all_results.count { |r| r[:success] }
    failed_sends = all_results.size - successful_sends

    puts "\n📊 Sending Summary:"
    puts "   ✅ Successful: #{successful_sends}"
    puts "   ❌ Failed:     #{failed_sends}"

    write_results_to_csv(all_results) if total_emails > 0
    puts "\n🎉 Email campaign completed!"
  end
end
