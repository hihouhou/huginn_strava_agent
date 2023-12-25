module Agents
  class StravaAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Strava Agent interacts with Strava's api.

      The `type` can be like get_activities.

      `debug` is used for verbose mode.

      `bearer_token` is mandatory for authentication.

      `refresh_token` is needed to refresh your token.

      `client_id` is mandatory for authentication.

      `client_secret` is mandatory for authentication.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "resource_state": 2,
            "athlete": {
              "id": XXXXXXXXX,
              "resource_state": 1
            },
            "name": "Afternoon Walk",
            "distance": 5091.0,
            "moving_time": 2454,
            "elapsed_time": 2472,
            "total_elevation_gain": 56.0,
            "type": "Walk",
            "sport_type": "Walk",
            "id": 10406902206,
            "start_date": "2023-11-11T13:45:53Z",
            "start_date_local": "2023-11-11T14:45:53Z",
            "timezone": "(GMT+01:00) Europe/Paris",
            "utc_offset": 3600.0,
            "location_city": null,
            "location_state": null,
            "location_country": "XXXXXX",
            "achievement_count": 0,
            "kudos_count": 0,
            "comment_count": 0,
            "athlete_count": 1,
            "photo_count": 0,
            "map": {
              "id": "XXXXXXXXXXXX",
              "summary_polyline": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
              "resource_state": 2
            },
            "trainer": false,
            "commute": false,
            "manual": false,
            "private": false,
            "visibility": "followers_only",
            "flagged": false,
            "gear_id": null,
            "start_latlng": [
              XXXXXXXXXXXXXXXXX,
              XXXXXXXXXXXXXXXXXX
            ],
            "end_latlng": [
              XXXXXXXXXXXXXXXXX,
              XXXXXXXXXXXXXXXXXX
            ],
            "average_speed": 2.075,
            "max_speed": 2.466,
            "average_cadence": 64.8,
            "average_temp": 20,
            "has_heartrate": false,
            "heartrate_opt_out": false,
            "display_hide_heartrate_option": false,
            "elev_high": 69.2,
            "elev_low": 23.4,
            "upload_id": XXXXXXXXXXX,
            "upload_id_str": "XXXXXXXXXXX",
            "external_id": "XXXXXXXXXXXXXXXXXXXXXXXX",
            "from_accepted_tag": false,
            "pr_count": 0,
            "total_photo_count": 0,
            "has_kudoed": false
          }
    MD

    def default_options
      {
        'type' => 'get_activities',
        'client_id' => '',
        'client_secret' => '',
        'refresh_token' => '',
        'bearer_token' => '',
        'debug' => 'false',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :type, type: :array, values: ['token_refresh', 'get_activities']
    form_configurable :client_id, type: :string
    form_configurable :client_secret, type: :string
    form_configurable :refresh_token, type: :string
    form_configurable :bearer_token, type: :string
    form_configurable :debug, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    def validate_options
      errors.add(:base, "type has invalid value: should be 'token_refresh' 'get_activities'") if interpolated['type'].present? && !%w(token_refresh get_activities).include?(interpolated['type'])

      unless options['client_id'].present?
        errors.add(:base, "client_id is a required field")
      end

      unless options['client_secret'].present?
        errors.add(:base, "client_secret is a required field")
      end

      unless options['refresh_token'].present?
        errors.add(:base, "refresh_token is a required field")
      end

      unless options['bearer_token'].present?
        errors.add(:base, "bearer_token is a required field")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          trigger_action
        end
      end
    end

    def check
      trigger_action
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "request status : #{code}"
        log "body"
        log body
      end

    end
    
    def token_refresh()

      uri = URI.parse("https://www.strava.com/api/v3/oauth/token")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        "client_id" => interpolated['client_id'],
        "client_secret" => interpolated['client_secret'],
        "grant_type" => "refresh_token",
        "refresh_token" => interpolated['refresh_token'],
      )
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      memory['expires_at'] = payload['expires_at']

    end
    
    def check_token_validity()

      if memory['expires_at'].nil?
        token_refresh()
      else
        timestamp_to_compare = memory['expires_at']
        current_timestamp = Time.now.to_i
        difference_in_hours = (timestamp_to_compare - current_timestamp) / 3600.0
        if difference_in_hours < 2
          token_refresh()
        else
          log "refresh not needed"
        end
      end

    end
    
    def get_activities()

      check_token_validity()
      uri = URI.parse("https://www.strava.com/api/v3/athlete/activities")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{interpolated['bearer_token']}"
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)

      if payload != memory['last_status']
        payload.each do |activity|        
          found = false
          if !memory['last_status'].nil? and memory['last_status']['activity'].present?
            last_status = memory['last_status']
            if interpolated['debug'] == 'true'
              log "last_status"
              log last_status
            end
            last_status.each do |activitybis|
              if activity == activitybis
                found = true
                if interpolated['debug'] == 'true'
                  log "found is #{found}"
                end
              end
            end
          end
          if found == false
            create_event payload: activity
          else
            if interpolated['debug'] == 'true'
              log "found is #{found}"
            end
          end
        end
        memory['last_status'] = payload
      else
        if interpolated['debug'] == 'true'
          log "no diff"
        end
      end

    end

    def trigger_action

      case interpolated['type']
      when "get_activities"
        get_activities()
      when "token_refresh"
        token_refresh()
      else
        log "Error: type has an invalid value (#{type})"
      end
    end
  end
end
