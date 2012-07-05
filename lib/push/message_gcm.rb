module Push
  class MessageGcm < Push::Message
    validates :collapse_key, :presence => true
    # TODO: validates max size -> The message size limit is 4096 bytes.
    # The total size of the payload data that is included in a message can't exceed 4096 bytes.
    # Note that this includes both the size of the keys as well as the values.

    store :properties, accessors: [:collapse_key, :delay_when_idle, :time_to_live, :payload]
    attr_accessible :device, :collapse_key, :delay_when_idle, :time_to_live, :payload

    def to_message
      hsh = Hash.new
      hsh['registration_ids'] = [device]
      hsh['collapse_key'] = collapse_key
      hsh['delay_when_idle'] = delay_when_idle if delay_when_idle
      hsh['time_to_live'] = time_to_live if time_to_live
      hsh['data'] = payload
      MultiJson.dump(hsh)
    end

    def use_connection
      Push::Daemon::GcmSupport::ConnectionGcm
    end

    private

    def check_for_error(connection)
      response = connection.response

      if response.code.eql? "200"
        hsh = MultiJson.load(response.body)
        if hsh["failure"] == 1
          msg = hsh["results"][0]["error"]

          # MissingRegistration, handled by validation
          # MismatchSenderId, configuration error by client
          # MessageTooBig, TODO: add validation

          if msg == "NotRegistered" or msg == "InvalidRegistration"
            with_database_reconnect_and_retry(connection.name) do
              Push::FeedbackGcm.create!(:failed_at => Time.now, :device => device) # follow-up: delete device
            end
          end

          Push::Daemon.logger.error("[#{connection.name}] Error received.")
          raise Push::DeliveryError.new(response.code, id, msg, "GCM")
        elsif hsh["canonical_ids"] == 1
          # success, but update device token
          # follow-up: delete device
          # with_database_reconnect_and_retry(connection.name) do
          #   Push::FeedbackGcm.create!(:failed_at => Time.now, :device => device) # follow-up: update device
          # end
        end
      else
        Push::Daemon.logger.error("[#{connection.name}] Error received.")
        raise Push::DeliveryError.new(response.code, id, response.body, "GCM")
      end
    end
  end
end