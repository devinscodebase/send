require 'optparse'
require 'tempfile'
require_relative 'mailgun_client'
require_relative 'config_manager'
require_relative 'csv_validator'
require_relative 'time_parser'

class CliInterface
  attr_reader :config, :client, :options

  def initialize
    @config = ConfigManager.new
    @options = {}
    setup_option_parser
  end

  def run
    parse_arguments
    validate_configuration
    setup_mailgun_client
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
      opts.banner = 'Usage: mailgun_sender [options]'
      opts.separator ''
      opts.separator 'Options:'

      opts.on('--domain=DOMAIN', 'Mailgun domain to send from') do |v|
        @options[:domain] = v
      end

      opts.on('--domain-key=KEY', 'API key for specific domain (if using domain sending key)') do |v|
        @options[:domain_key] = v
      end

      opts.on('--csv=FILE', 'Path to contacts CSV file') do |v|
        @options[:csv_file] = v
      end

      opts.on('--template=FILE', 'Path to HTML template file') do |v|
        @options[:template_file] = v
      end

      opts.on('--from=EMAIL', 'From address (default: postmaster@domain)') do |v|
        @options[:from_address] = v
      end

      opts.on('--subject=TEXT', 'Email subject line') do |v|
        @options[:subject] = v
      end

      opts.on('--send-at=TIME', "Scheduled send time (e.g. '2025-08-08 10:00 EST', 'tomorrow 9am')") do |v|
        @options[:send_time] = v
      end

      opts.on('--list-name=NAME', 'Mailing list name (default: derived from CSV filename)') do |v|
        @options[:list_name] = v
      end

      opts.on('--test', 'Enable test mode (no actual send)') do
        @options[:test_mode] = true
      end

      opts.on('--dry-run', 'Show what would be done without making API calls') do
        @options[:dry_run] = true
      end

      opts.on('--max-threads=NUM', Integer, 'Maximum parallel threads (default: 5)') do |v|
        @options[:max_threads] = v
      end

      opts.on('--delay=SECONDS', Float, 'Delay between requests in seconds (default: 0.1)') do |v|
        @options[:delay_between_requests] = v
      end

      opts.on('--config=FILE', 'Path to configuration file') do |v|
        @options[:config_file] = v
      end

      opts.on('-v', '--verbose', 'Enable verbose output') do
        @options[:verbose] = true
      end

      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit
      end

      opts.on('--version', 'Show version') do
        puts 'Mailgun CLI Bulk Email Sender v1.0.0'
        exit
      end
    end
  end

  def parse_arguments
    @option_parser.parse!(into: @options)
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
    puts "Error: #{e.message}"
    puts @option_parser
    exit 1
  end

  def validate_configuration
    errors = @config.validate_required_fields
    unless errors.empty?
      puts 'Configuration errors:'
      errors.each { |error| puts "  - #{error}" }
      exit 1
    end
  end

  def setup_mailgun_client
    @client = MailgunClient.new(@config.api_key, @config.base_url)
  end

  def execute_workflow
    puts '🚀 Mailgun CLI Bulk Email Sender'
    puts '=' * 50

    # Gather all required information
    domain = get_domain
    csv_file = get_csv_file
    template_file = get_template_file
    from_address = get_from_address(domain)
    subject = get_subject
    send_time = get_send_time
    list_name = get_list_name(csv_file)
    test_mode = get_test_mode

    # Validate CSV
    puts "\n📋 Validating CSV file..."
    csv_validator = CsvValidator.new(csv_file)
    unless csv_validator.validate_and_parse
      puts 'CSV validation failed:'
      csv_validator.errors.each { |error| puts "  ❌ #{error}" }
      exit 1
    end

    puts '✅ CSV validation successful'
    puts "   Total contacts: #{csv_validator.contact_count}"
    puts "   Valid contacts: #{csv_validator.valid_contact_count}"
    puts "   Invalid contacts: #{csv_validator.invalid_contact_count}"

    if csv_validator.invalid_contact_count.positive?
      puts "\n⚠️  Warnings:"
      csv_validator.warnings.each { |warning| puts "  ⚠️  #{warning}" }
    end

    # Load template
    puts "\n📄 Loading email template..."
    html_content = load_template(template_file)
    puts "✅ Template loaded (#{html_content.length} characters)"

    # Generate valid CSV for upload
    valid_csv_path = generate_valid_csv(csv_validator)

    # Summary and confirmation
    show_summary(domain, list_name, csv_validator.valid_contact_count, from_address, subject, send_time, test_mode)

    unless confirm_operation
      puts 'Operation cancelled.'
      exit 0
    end

    # Execute the send operation
    if @options[:dry_run]
      perform_dry_run(domain, list_name, valid_csv_path, from_address, subject, html_content, send_time, test_mode)
    else
      perform_send(domain, list_name, valid_csv_path, from_address, subject, html_content, send_time, test_mode)
    end
  end

  def get_domain
    if @options[:domain]
      # If domain is specified via command line, try to get its key
      if @config.domain_keys[@options[:domain]]
        @options[:domain_key] = @config.domain_keys[@options[:domain]]
        puts "✅ Using domain-specific API key for #{@options[:domain]}"
      end
      return @options[:domain]
    end
    return @config.domain if @config.domain

    # Check if we have domains from domains.env
    if @config.domains.any?
      puts "\n🌐 Available domains from configuration:"
      @config.domains.each_with_index do |domain, index|
        has_key = @config.domain_keys[domain] ? '✅' : '❌'
        puts "  [#{index + 1}] #{domain} #{has_key}"
      end

      print "Select domain (1-#{@config.domains.length}): "
      choice = gets.chomp.to_i

      if choice < 1 || choice > @config.domains.length
        puts 'Invalid selection.'
        exit 1
      end

      selected_domain = @config.domains[choice - 1]

      # Set the domain-specific API key if available
      if @config.domain_keys[selected_domain]
        @options[:domain_key] = @config.domain_keys[selected_domain]
        puts "✅ Using domain-specific API key for #{selected_domain}"
      else
        puts "⚠️  No domain-specific API key found for #{selected_domain}"
      end

      return selected_domain
    end

    # Fallback to fetching from Mailgun API
    puts "\n🌐 Fetching available domains from Mailgun API..."
    begin
      domains = @client.list_domains
      if domains.empty?
        puts '❌ No domains found in your Mailgun account.'
        exit 1
      end

      puts 'Available domains:'
      domains.each_with_index do |domain, index|
        puts "  [#{index + 1}] #{domain['name']}"
      end

      print "Select domain (1-#{domains.length}): "
      choice = gets.chomp.to_i

      if choice < 1 || choice > domains.length
        puts 'Invalid selection.'
        exit 1
      end

      domains[choice - 1]['name']
    rescue MailgunError => e
      puts "❌ Failed to fetch domains: #{e.message}"
      puts '💡 Tip: You can configure domains in domains.env file'
      exit 1
    end
  end

  def get_csv_file
    return @options[:csv_file] if @options[:csv_file]

    print 'Enter path to contacts CSV file: '
    file_path = gets.chomp.strip

    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      exit 1
    end

    file_path
  end

  def get_template_file
    return @options[:template_file] if @options[:template_file]

    print 'Enter path to HTML template file: '
    file_path = gets.chomp.strip

    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      exit 1
    end

    file_path
  end

  def get_from_address(domain)
    from_address = @options[:from_address] || @config.from_address

    if from_address.nil?
      default_from = "postmaster@#{domain}"
      print "Enter sender email (or press Enter for #{default_from}): "
      from_address = gets.chomp.strip
      from_address = default_from if from_address.empty?
    end

    # Add sender name for specific domains
    if from_address.include?('retirementaid.org')
      from_address = "Grant Walker <#{from_address}>"
    elsif from_address.include?('pensionaid.org')
      from_address = "Grant Walker <#{from_address}>"
    end

    from_address
  end

  def get_subject
    return @options[:subject] if @options[:subject]

    print 'Enter email subject: '
    subject = gets.chomp.strip

    if subject.empty?
      puts '❌ Subject is required.'
      exit 1
    end

    subject
  end

  def get_send_time
    return @options[:send_time] if @options[:send_time]

    print "Enter send date/time (e.g. '2025-08-08 10:00 EST', 'tomorrow 9am', or 'now'): "
    time_string = gets.chomp.strip

    return nil if time_string.empty?

    begin
      TimeParser.parse_schedule_time(time_string)
    rescue TimeParseError => e
      puts "❌ #{e.message}"
      exit 1
    end
  end

  def get_list_name(csv_file)
    return @options[:list_name] if @options[:list_name]
    return @config.list_name if @config.list_name

    # Derive from CSV filename
    base_name = File.basename(csv_file, '.*')
    list_name = base_name.gsub(/[^a-zA-Z0-9_-]/, '_').downcase

    print "Enter mailing list name (or press Enter for '#{list_name}'): "
    user_list_name = gets.chomp.strip

    user_list_name.empty? ? list_name : user_list_name
  end

  def get_test_mode
    return @options[:test_mode] if @options.key?(:test_mode)

    print 'Test mode? (y/N): '
    response = gets.chomp.strip.downcase

    %w[y yes].include?(response)
  end

  def load_template(template_file)
    content = File.read(template_file)
    content.force_encoding('UTF-8')

    content
  rescue StandardError => e
    puts "❌ Failed to load template: #{e.message}"
    exit 1
  end

  def generate_valid_csv(csv_validator)
    valid_contacts = csv_validator.contacts.select { |contact| contact[:valid] }

    temp_file = Tempfile.new(['valid_contacts', '.csv'])
    CSV.open(temp_file.path, 'w') do |csv|
      csv << %w[address firstname lastname company]
      valid_contacts.each do |contact|
        csv << [contact[:email], contact[:firstname] || '', contact[:lastname] || '', contact[:company] || '']
      end
    end

    temp_file.path
  end

  def show_summary(domain, list_name, contact_count, from_address, subject, send_time, test_mode)
    puts "\n#{'=' * 50}"
    puts '📧 EMAIL SEND SUMMARY'
    puts '=' * 50
    puts "Domain: #{domain}"
    puts "Mailing List: #{list_name}@#{domain}"
    puts "Recipients: #{contact_count}"
    puts "From: #{from_address}"
    puts "Subject: #{subject}"
    puts "Scheduled: #{send_time || 'Send immediately'}"
    puts "Test Mode: #{test_mode ? 'Yes' : 'No'}"
    puts '=' * 50
  end

  def confirm_operation
    print "\nProceed with sending? (y/N): "
    response = gets.chomp.strip.downcase

    %w[y yes].include?(response)
  end

  def perform_dry_run(domain, _list_name, csv_file, from_address, subject, html_content, send_time, test_mode)
    puts "\n🔍 DRY RUN MODE - No actual API calls will be made"
    puts '=' * 50

    # Count recipients
    recipient_count = CSV.read(csv_file).count - 1

    puts "Would send emails directly to #{recipient_count} recipients from: #{csv_file}"
    puts "Would send email with subject: #{subject}"
    puts "From: #{from_address}"
    puts "Domain: #{domain}"
    puts "Scheduled: #{send_time || 'Send immediately'}"
    puts "Test Mode: #{test_mode ? 'Yes' : 'No'}"
    puts "Template size: #{html_content.length} characters"

    puts "\n✅ Dry run completed successfully!"
  end

  def perform_send(domain, _list_name, csv_file, from_address, subject, html_content, send_time, test_mode)
    puts "\n📤 Starting email send process..."
    puts '=' * 50

    # Load recipients from CSV
    puts '📋 Loading recipients from CSV...'
    recipients = []
    CSV.foreach(csv_file, headers: true) do |row|
      email = row['email'] || row['Email'] || row['EMAIL'] || row['address'] || row['Address']
      firstname = row['firstname'] || row['Firstname'] || row['FIRSTNAME'] || row['first_name'] || row['First Name']
      lastname = row['lastname'] || row['Lastname'] || row['LASTNAME'] || row['last_name'] || row['Last Name']
      company = row['company'] || row['Company'] || row['COMPANY']

      # Fallback to old 'name' format if firstname/lastname not found
      if firstname.nil? && lastname.nil?
        name = row['name'] || row['Name'] || row['NAME']
        if name
          name_parts = name.split(' ', 2)
          firstname = name_parts[0]
          lastname = name_parts[1] || ''
        end
      end

      if email && !email.strip.empty?
        recipients << {
          email: email.strip,
          firstname: firstname&.strip || '',
          lastname: lastname&.strip || '',
          company: company&.strip
        }
        full_name = [firstname&.strip, lastname&.strip].compact.join(' ')
        puts "  📧 #{email.strip} (#{full_name || 'No name'})"
      else
        puts '  ⚠️  Skipping row with empty email'
      end
    end

    puts "✅ Loaded #{recipients.length} recipients"

    # Send emails directly to each recipient
    puts '📧 Sending emails to individual recipients...'
    begin
      send_options = {}
      send_options[:delivery_time] = send_time if send_time
      send_options[:test_mode] = test_mode
      send_options[:domain_key] = @options[:domain_key] if @options[:domain_key]
      send_options[:max_threads] = @options[:max_threads] if @options[:max_threads]
      send_options[:delay_between_requests] = @options[:delay_between_requests] if @options[:delay_between_requests]

      results = @client.send_bulk_emails(domain, from_address, recipients, subject, html_content, send_options)

      # Summary
      successful = results.count { |r| r[:success] }
      failed = results.count { |r| !r[:success] }

      puts "\n📊 Sending Summary:"
      puts "   ✅ Successful: #{successful}"
      puts "   ❌ Failed: #{failed}"
      puts "   📧 Total: #{results.length}"

      if test_mode
        puts 'ℹ️  Test mode enabled - no actual emails were sent'
      end

      if send_time
        puts "⏰ Emails scheduled for: #{send_time}"
      end
    rescue MailgunError => e
      puts "❌ Failed to send emails: #{e.message}"
      exit 1
    end

    puts "\n🎉 Email campaign completed successfully!"
    puts 'You can monitor delivery status on your Mailgun dashboard.'
  end
end
