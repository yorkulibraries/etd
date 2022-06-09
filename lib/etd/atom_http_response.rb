module Atom
  module HTTPResponse
    
    # this should probably support ranges (eg. text/*)
    def validate_content_type( valid )              
      raise Atom::HTTPException, "HTTP response contains no Content-Type!" if not self.content_type or self.content_type.empty?
      
      media_type = self.content_type.split(";").first
      if media_type == "application/atomserv+xml"
        self.content_type = "application/atomsvc+xml"
        media_type = "application/atomsvc+xml" 
      end
      
      unless valid.member? media_type.downcase
        raise Atom::WrongMimetype, "unexpected response Content-Type: #{media_type.inspect}. should be one of: #{valid.inspect}"
      end
    end
  end
end