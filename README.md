# Mailgun CLI Bulk Email Sender

A powerful command-line interface (CLI) tool for sending bulk emails via the Mailgun API. Built with Ruby and designed for developers and marketers who need to send personalized email campaigns efficiently.

## ⚠️ Current Status & Known Issues

### 🐛 Known Bugs & Limitations

1. **Mailgun Account Probation**: 
   - New accounts are limited to 100 messages/hour
   - Account probation periods can last 24-48 hours
   - Error: `"Your account is on probation and domains are limited to 100 messages / hour"`

2. **Rate Limiting Issues**:
   - Even conservative settings (3 threads, 0.2s delay) can exceed limits
   - Large campaigns (>100 emails) often hit rate limits
   - Error: `"Rate limit exceeded. Please wait before retrying"`

3. **Domain Sending Limits**:
   - Individual domains have recipient limits
   - Error: `"Domain is not allowed to send: recipient limit exceeded"`

4. **API Key Authentication**:
   - Domain-specific sending keys only work for sending, not domain management
   - Primary account API key required for domain listing and list management

### 🔧 Current Logic & Architecture

- **Direct Individual Sending**: No longer creates mailing lists, sends directly to each recipient
- **Local Personalization**: Performs string replacement in HTML templates locally before sending
- **Parallel Processing**: Uses Ruby's `parallel` gem for concurrent email sending
- **Retry Logic**: Automatic retry with exponential backoff for rate limit errors
- **CSV Support**: Now supports `firstname`/`lastname` columns in addition to `name`

## Features

- 🔐 **Secure Authentication**: Uses environment variables for API credentials
- 📧 **Bulk Email Sending**: Send to thousands of recipients with one command
- 📋 **CSV Contact Import**: Upload contact lists with validation
- 🎨 **HTML Template Support**: Use custom HTML templates with personalization
- ⏰ **Scheduled Sending**: Schedule emails for specific times (EST/EDT)
- 🧪 **Test Mode**: Safe testing with dry-run and test mode options
- 🌐 **Domain Management**: Automatic domain discovery and selection
- 📊 **Contact Validation**: Validate email addresses and contact data
- ⚙️ **Configuration Files**: Set defaults for common options
- 🎯 **Personalization**: Support for local template variable replacement
- 🚀 **Parallel Processing**: Concurrent email sending with rate limiting
- 🔄 **Retry Logic**: Automatic retry for rate limit errors

## Installation

### Prerequisites

- Ruby 3.0 or higher
- A Mailgun account with API access
- Your Mailgun API key (Primary Account API Key for domain management)
- Domain-specific sending keys for actual email sending

### Setup

1. **Clone or download the project**
   ```bash
   git clone <repository-url>
   cd mailgun-cli-sender
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Configure your API credentials**
   ```bash
   cp env.example .env
   cp domains.env.example domains.env
   ```
   
   Edit `.env` and add your Mailgun API key:
   ```bash
   MAILGUN_API_KEY=key-your-actual-api-key-here
   MAILGUN_API_BASE_URL=https://api.mailgun.net  # or https://api.eu.mailgun.net for EU
   ```
   
   Edit `domains.env` and add your domain-specific sending keys:
   ```bash
   MAILGUN_DOMAINS=mg.pensionaid.org,mg.retirementaid.org
   MG_DOMAIN_PENSIONAID_ORG_KEY=key-domain-specific-sending-key
   MG_DOMAIN_RETIREMENTAID_ORG_KEY=key-domain-specific-sending-key
   ```

4. **Make the script executable**
   ```bash
   chmod +x mailgun_sender.rb
   ```

## Quick Start

### Basic Usage

Run the script interactively:
```bash
./mailgun_sender.rb
```

The CLI will prompt you for:
- Domain selection (fetched from your Mailgun account or domains.env)
- CSV file path
- HTML template file path
- Sender email address
- Subject line
- Send time (optional)
- Test mode confirmation

### Command Line Options

Use flags for non-interactive operation:
```bash
./mailgun_sender.rb \
  --domain="example.com" \
  --csv="contacts.csv" \
  --template="newsletter.html" \
  --from="marketing@example.com" \
  --subject="Monthly Newsletter" \
  --send-at="2025-01-15 10:00 EST" \
  --test
```

### Available Options

| Option | Description | Example |
|--------|-------------|---------|
| `--domain` | Mailgun domain to send from | `--domain=example.com` |
| `--csv` | Path to contacts CSV file | `--csv=contacts.csv` |
| `--template` | Path to HTML template file | `--template=newsletter.html` |
| `--from` | Sender email address | `--from=marketing@example.com` |
| `--subject` | Email subject line | `--subject="Newsletter"` |
| `--send-at` | Scheduled send time | `--send-at="tomorrow 9am"` |
| `--test` | Enable test mode | `--test` |
| `--dry-run` | Show what would be done | `--dry-run` |
| `--max-threads=NUM` | Maximum parallel threads (default: 5) | `--max-threads=3` |
| `--delay=SECONDS` | Delay between requests in seconds (default: 0.1) | `--delay=0.2` |
| `--verbose` | Enable verbose output | `--verbose` |
| `--help` | Show help message | `--help` |

## File Formats

### CSV Contact File

Your CSV should have headers and include email and name columns:

```csv
email,firstname,lastname,company
john.doe@example.com,John,Doe,Acme Corp
jane.smith@example.com,Jane,Smith,Tech Solutions
```

**Supported column names for email:**
- `email`, `Email`, `EMAIL`
- `address`, `Address`

**Supported column names for names:**
- `firstname`, `Firstname`, `FIRSTNAME`, `first_name`, `First Name`
- `lastname`, `Lastname`, `LASTNAME`, `last_name`, `Last Name`
- `name`, `Name`, `NAME` (fallback, will be split into first/last)

### HTML Template

Use local template variables for personalization (replaced before sending):

```html
<!DOCTYPE html>
<html>
<body>
    <h1>Hello %recipient.first%,</h1>
    <p>Welcome to our newsletter, %recipient.name%!</p>
    <p>Your company: %recipient.company%</p>
    
    <!-- Sender signature -->
    <div style="text-align: center;">
        <img src="%sender.profile_picture%" alt="%sender.name%" style="width: 65px; height: 65px; border-radius: 8px;">
        <p><strong>%sender.name%</strong><br>
        %sender.title%<br>
        %sender.email%</p>
    </div>
</body>
</html>
```

**Available template variables:**
- `%recipient.first%` - First name
- `%recipient.name%` - Full name
- `%recipient.company%` - Company name
- `%sender.name%` - Sender's full name
- `%sender.title%` - Sender's title
- `%sender.email%` - Sender's email
- `%sender.profile_picture%` - Sender's profile picture URL

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
MAILGUN_API_KEY=key-your-primary-api-key
MAILGUN_API_BASE_URL=https://api.mailgun.net
```

Create a `domains.env` file for domain-specific sending keys:

```bash
MAILGUN_DOMAINS=mg.pensionaid.org,mg.retirementaid.org
MG_DOMAIN_PENSIONAID_ORG_KEY=key-domain-specific-sending-key
MG_DOMAIN_RETIREMENTAID_ORG_KEY=key-domain-specific-sending-key
```

### Configuration File

Create a `config.yml` file for default values:

```yaml
default_domain: "mg.pensionaid.org"
default_from: "Grant Walker <grant@mg.pensionaid.org>"
default_subject: "Your Retirement Consultation"
```

## Time Scheduling

The tool supports various time formats:

- **Exact date/time**: `2025-01-15 10:00 EST`
- **Relative times**: `tomorrow 9am`, `next monday 2pm`
- **Time only**: `9:30am` (schedules for today or tomorrow)
- **Immediate**: `now`

All times are interpreted in Eastern Time (EST/EDT).

## Examples

### Send a Test Newsletter

```bash
./mailgun_sender.rb \
  --domain="mg.pensionaid.org" \
  --csv="contacts/contacts.csv" \
  --template="templates/newsletter_template.html" \
  --subject="Test Newsletter" \
  --test
```

### Retirement Consultation Campaign

```bash
./mailgun_sender.rb \
  --domain="mg.pensionaid.org" \
  --csv="contacts/retirement_contacts.csv" \
  --template="templates/U1.html" \
  --subject="Your Retirement Consultation - Ready to Schedule?" \
  --from="grant@mg.pensionaid.org"
```

### Schedule a Campaign

```bash
./mailgun_sender.rb \
  --domain="mg.pensionaid.org" \
  --csv="contacts/fl-valid-500.csv" \
  --template="templates/U1.html" \
  --subject="Your Retirement Consultation - Ready to Schedule?" \
  --from="grant@mg.pensionaid.org" \
  --send-at="2025-01-20 09:00 EST"
```

### Dry Run (Preview)

```bash
./mailgun_sender.rb \
  --domain="mg.pensionaid.org" \
  --csv="contacts/contacts.csv" \
  --template="templates/U1.html" \
  --dry-run
```

## Error Handling

The tool provides comprehensive error handling:

- **API Errors**: Displays specific Mailgun error messages
- **File Errors**: Validates CSV and template files
- **Validation Errors**: Checks email formats and required fields
- **Rate Limiting**: Handles Mailgun API rate limits with automatic retry

## Security Features

- API keys stored in environment variables (never logged)
- Secure HTTP requests with TLS
- Input validation and sanitization
- Test mode for safe experimentation
- Domain-specific sending keys for enhanced security

## Troubleshooting

### Common Issues

1. **"Authentication failed"**
   - Check your API key in the `.env` file
   - Verify the key is active in your Mailgun dashboard
   - Ensure you're using the correct key type (Primary vs Domain Sending)

2. **"No domains found"**
   - Ensure your Mailgun account has verified domains
   - Check your API key permissions
   - Verify domains are listed in `domains.env`

3. **"CSV validation failed"**
   - Ensure your CSV has proper headers (`email`, `firstname`, `lastname`)
   - Check for valid email addresses
   - Verify file encoding (UTF-8 recommended)

4. **"Template not found"**
   - Check the file path
   - Ensure the file is readable

5. **"Rate limit exceeded"**
   - Reduce `--max-threads` to 1-2
   - Increase `--delay` to 0.5-1.0 seconds
   - Wait for probation period to end (24-48 hours)

6. **"Account on probation"**
   - New Mailgun accounts are limited to 100 messages/hour
   - Wait 24-48 hours for probation to end
   - Consider upgrading your Mailgun plan

### Debug Mode

Enable debug output:
```bash
DEBUG=1 ./mailgun_sender.rb
```

## API Limits & Rate Limiting

### Current Mailgun Limits

- **New Account Probation**: 100 messages/hour for first 24-48 hours
- **Rate Limits**: 10-20 emails per second (varies by plan)
- **Domain Limits**: Individual domains have recipient limits
- **Account Limits**: Varies by plan (Free: 5,000 emails/month)

### Rate Limiting Strategy

The tool includes built-in rate limiting to respect Mailgun's API limits:

- **Ultra Conservative**: `--max-threads=1 --delay=1.0` (1 email/second)
- **Conservative**: `--max-threads=3 --delay=0.2` (3 emails/second)
- **Default**: `--max-threads=5 --delay=0.1` (5 emails/second)
- **Aggressive**: `--max-threads=8 --delay=0.05` (8 emails/second - use with caution)

**Recommended for large campaigns:**
```bash
# Ultra conservative for new accounts or probation periods
./mailgun_sender.rb \
  --domain="mg.pensionaid.org" \
  --csv="large_list.csv" \
  --template="templates/U1.html" \
  --max-threads=1 \
  --delay=1.0
```

### Handling Failed Sends

When campaigns are interrupted by rate limits:

1. **Check the output** for successful vs failed sends
2. **Create separate CSV files**:
   - `sent.csv` - Successfully sent emails
   - `needtosend.csv` - Failed or unprocessed emails
3. **Retry with more conservative settings**:
   ```bash
   ./mailgun_sender.rb \
     --domain="mg.pensionaid.org" \
     --csv="needtosend.csv" \
     --template="templates/U1.html" \
     --max-threads=1 \
     --delay=1.0
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section
- Review Mailgun's API documentation
- Open an issue on GitHub

## Changelog

### v1.1.0 (Current)
- **BREAKING**: Removed mailing list creation, now sends directly to individual recipients
- **NEW**: Local template personalization (no more Mailgun recipient-variables)
- **NEW**: Support for `firstname`/`lastname` CSV columns
- **NEW**: Domain-specific sending keys support
- **NEW**: Parallel processing with rate limiting
- **NEW**: Automatic retry logic for rate limit errors
- **NEW**: Sender signature with profile picture support
- **FIXED**: Personalization variable replacement
- **FIXED**: CSV parsing and validation
- **KNOWN ISSUES**: Rate limiting and account probation limits

### v1.0.0
- Initial release
- Basic bulk email functionality
- CSV import and validation
- HTML template support
- Scheduling capabilities
- Test mode and dry-run options
