require 'time'
require 'tzinfo'

class TimeParser
  EASTERN_TZ = TZInfo::Timezone.get('America/New_York')

  def self.parse_schedule_time(time_string)
    return nil if time_string.nil? || time_string.strip.empty?

    time_string = time_string.strip.downcase

    case time_string
    when 'now'
      format_for_mailgun(Time.now)
    when /^(\d{1,2}):(\d{2})\s*(am|pm)?$/i
      # Time only (e.g., "9:30am", "14:30")
      parse_time_only(::Regexp.last_match(1), ::Regexp.last_match(2), ::Regexp.last_match(3))
    when /^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})\s*(am|pm)?$/i
      # Date and time (e.g., "2025-08-08 10:00am")
      parse_date_time(::Regexp.last_match(1), ::Regexp.last_match(2), ::Regexp.last_match(3), ::Regexp.last_match(4),
                      ::Regexp.last_match(5), ::Regexp.last_match(6))
    when %r{^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2})\s*(am|pm)?$}i
      # US date format (e.g., "08/08/2025 10:00am")
      parse_us_date_time(::Regexp.last_match(1), ::Regexp.last_match(2), ::Regexp.last_match(3),
                         ::Regexp.last_match(4), ::Regexp.last_match(5), ::Regexp.last_match(6))
    when /^tomorrow\s+(\d{1,2}):(\d{2})\s*(am|pm)?$/i
      # Tomorrow with time (e.g., "tomorrow 9am")
      parse_tomorrow_time(::Regexp.last_match(1), ::Regexp.last_match(2), ::Regexp.last_match(3))
    when /^next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(\d{1,2}):(\d{2})\s*(am|pm)?$/i
      # Next weekday with time (e.g., "next monday 9am")
      parse_next_weekday(::Regexp.last_match(1), ::Regexp.last_match(2), ::Regexp.last_match(3), ::Regexp.last_match(4))
    else
      # Try to parse as a general time string
      begin
        time = Time.parse(time_string)
        format_for_mailgun(time)
      rescue ArgumentError
        raise TimeParseError,
              "Unable to parse time: #{time_string}. Use formats like '2025-08-08 10:00am', 'tomorrow 9am', or 'now'"
      end
    end
  end

  def self.validate_schedule_time(scheduled_time)
    return true if scheduled_time.nil? # No scheduling

    begin
      time = Time.parse(scheduled_time)
      now = Time.now

      if time <= now
        raise TimeParseError, 'Scheduled time must be in the future'
      end

      # Check if within 7 days (Mailgun limit for most plans)
      if time > now + (7 * 24 * 60 * 60)
        raise TimeParseError, 'Scheduled time cannot be more than 7 days in the future'
      end

      true
    rescue ArgumentError
      raise TimeParseError, "Invalid time format: #{scheduled_time}"
    end
  end

  def self.parse_time_only(hour, minute, ampm)
    hour = hour.to_i
    minute = minute.to_i

    # Handle AM/PM
    if ampm
      if ampm.downcase == 'pm' && hour != 12
        hour += 12
      elsif ampm.downcase == 'am' && hour == 12
        hour = 0
      end
    end

    # Schedule for today at the specified time
    now = Time.now
    eastern_offset = EASTERN_TZ.current_period.offset.utc_total_offset
    scheduled_time = Time.new(now.year, now.month, now.day, hour, minute, 0, eastern_offset)

    # If the time has already passed today, schedule for tomorrow
    if scheduled_time <= now
      scheduled_time += 24 * 60 * 60
    end

    format_for_mailgun(scheduled_time)
  end

  def self.parse_date_time(year, month, day, hour, minute, ampm)
    year = year.to_i
    month = month.to_i
    day = day.to_i
    hour = hour.to_i
    minute = minute.to_i

    # Handle AM/PM
    if ampm
      if ampm.downcase == 'pm' && hour != 12
        hour += 12
      elsif ampm.downcase == 'am' && hour == 12
        hour = 0
      end
    end

    eastern_offset = EASTERN_TZ.current_period.offset.utc_total_offset
    scheduled_time = Time.new(year, month, day, hour, minute, 0, eastern_offset)
    format_for_mailgun(scheduled_time)
  end

  def self.parse_us_date_time(month, day, year, hour, minute, ampm)
    parse_date_time(year, month, day, hour, minute, ampm)
  end

  def self.parse_tomorrow_time(hour, minute, ampm)
    hour = hour.to_i
    minute = minute.to_i

    # Handle AM/PM
    if ampm
      if ampm.downcase == 'pm' && hour != 12
        hour += 12
      elsif ampm.downcase == 'am' && hour == 12
        hour = 0
      end
    end

    now = Time.now
    tomorrow = now + (24 * 60 * 60)
    scheduled_time = Time.new(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute, 0, EASTERN_TZ)

    format_for_mailgun(scheduled_time)
  end

  def self.parse_next_weekday(weekday, hour, minute, ampm)
    hour = hour.to_i
    minute = minute.to_i

    # Handle AM/PM
    if ampm
      if ampm.downcase == 'pm' && hour != 12
        hour += 12
      elsif ampm.downcase == 'am' && hour == 12
        hour = 0
      end
    end

    weekday_map = {
      'monday' => 1, 'tuesday' => 2, 'wednesday' => 3,
      'thursday' => 4, 'friday' => 5, 'saturday' => 6, 'sunday' => 0
    }

    target_wday = weekday_map[weekday.downcase]
    now = Time.now
    days_ahead = (target_wday - now.wday) % 7
    days_ahead = 7 if days_ahead.zero? # If today is the target day, go to next week

    target_date = now + (days_ahead * 24 * 60 * 60)
    eastern_offset = EASTERN_TZ.current_period.offset.utc_total_offset
    scheduled_time = Time.new(target_date.year, target_date.month, target_date.day, hour, minute, 0, eastern_offset)

    format_for_mailgun(scheduled_time)
  end

  def self.format_for_mailgun(time)
    # Convert to Eastern time and format as RFC 2822
    # Handle time zone conversion manually since we're not using ActiveSupport
    eastern_offset = EASTERN_TZ.current_period.offset.utc_total_offset
    eastern_time = time + eastern_offset - time.utc_offset
    eastern_time.strftime('%a, %d %b %Y %H:%M:%S %z')
  end
end

class TimeParseError < StandardError; end
