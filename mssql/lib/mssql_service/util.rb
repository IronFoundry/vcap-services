# Copyright (c) 2011 Tier3, Inc.
module VCAP
  module Services
    module MSSQL
      module Util
        VALID_CREDENTIAL_CHARACTERS = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a
        def generate_credential(length=12)
          Array.new(length) { VALID_CREDENTIAL_CHARACTERS[rand(VALID_CREDENTIAL_CHARACTERS.length)] }.join
        end
      end
    end
  end
end
