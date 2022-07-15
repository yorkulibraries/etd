require 'net/http'

# Lengthen timeout in Net::HTTP
module Net
  class HTTP
    alias old_initialize initialize

    def initialize(*args)
      old_initialize(*args)
      @read_timeout = 60 * 60     # 60 minutes
    end
  end
end
