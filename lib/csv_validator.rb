require 'csv'

class CsvValidator
  attr_reader :contacts, :errors, :warnings

  def initialize(csv_file_path)
    @csv_file_path = csv_file_path
    @contacts = []
    @errors = []
    @warnings = []
  end

  def validate_and_parse
    return false unless file_exists?
    return false unless valid_csv_format?

    parse_contacts
    validate_contacts
    true
  end

  def contact_count
    @contacts.length
  end

  def valid_contact_count
    @contacts.count { |contact| contact[:valid] }
  end

  def invalid_contact_count
    @contacts.count { |contact| !contact[:valid] }
  end

  def generate_valid_csv
    valid_contacts = @contacts.select { |contact| contact[:valid] }

    temp_file = Tempfile.new(['valid_contacts', '.csv'])
    CSV.open(temp_file.path, 'w') do |csv|
      # Write header
      csv << %w[address firstname lastname company]

      # Write valid contacts
      valid_contacts.each do |contact|
        csv << [contact[:email], contact[:firstname] || '', contact[:lastname] || '', contact[:company] || '']
      end
    end

    temp_file.path
  end

  private

  def file_exists?
    unless File.exist?(@csv_file_path)
      @errors << "CSV file not found: #{@csv_file_path}"
      return false
    end
    true
  end

  def valid_csv_format?
    CSV.foreach(@csv_file_path, headers: true).first
    true
  rescue CSV::MalformedCSVError => e
    @errors << "Invalid CSV format: #{e.message}"
    false
  end

  def parse_contacts
    CSV.foreach(@csv_file_path, headers: true).with_index(1) do |row, line_number|
      contact = parse_contact(row, line_number)
      @contacts << contact
    end
  end

  def parse_contact(row, line_number)
    email = row['email'] || row['Email'] || row['EMAIL'] || row['address'] || row['Address']
    
    # Support both old 'name' format and new 'firstname'/'lastname' format
    firstname = row['firstname'] || row['Firstname'] || row['FIRSTNAME'] || row['first_name'] || row['First Name']
    lastname = row['lastname'] || row['Lastname'] || row['LASTNAME'] || row['last_name'] || row['Last Name']
    
    # Fallback to old 'name' format if firstname/lastname not found
    if firstname.nil? && lastname.nil?
      name = row['name'] || row['Name'] || row['NAME']
      if name
        name_parts = name.split(' ', 2)
        firstname = name_parts[0]
        lastname = name_parts[1] || ''
      end
    end
    
    company = row['company'] || row['Company'] || row['COMPANY']

    {
      line_number: line_number,
      email: email&.strip,
      firstname: firstname&.strip || '',
      lastname: lastname&.strip || '',
      company: company&.strip,
      raw_data: row.to_h,
      valid: false
    }
  end

  def validate_contacts
    @contacts.each do |contact|
      validate_contact(contact)
    end
  end

  def validate_contact(contact)
    if contact[:email].nil? || contact[:email].empty?
      contact[:valid] = false
      @errors << "Line #{contact[:line_number]}: Missing email address"
      return
    end

    unless valid_email_format?(contact[:email])
      contact[:valid] = false
      @errors << "Line #{contact[:line_number]}: Invalid email format: #{contact[:email]}"
      return
    end

    if contact[:firstname].nil? || contact[:firstname].empty?
      @warnings << "Line #{contact[:line_number]}: Missing firstname for #{contact[:email]}"
    end

    contact[:valid] = true
  end

  def valid_email_format?(email)
    email_regex = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
    email_regex.match?(email)
  end
end
