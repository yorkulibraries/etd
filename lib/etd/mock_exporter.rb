require 'ostruct'

module ETD
  class MockExporter

    def prepare_collection
      # do nothing
    end

    def deposit(params = {})
      #return receipt or throw exception based on predetermined attribute value
      p = OpenStruct.new(params)


      if ETD::MockExporter.get_entry_value(p.entry, "title").include?("FAIL")
        raise Exception.new("Error is found")
      end

      return OpenStruct.new({
        status_code: 1234,
        status_message: "Deposited correctly"
        })

    end
  end

  def MockExporter.get_entry_value(entry, field)
    return nil if entry == nil
    entry.extensions.each_entry do |e|
      return e.text if e.name == field
    end

    return ""
  end
end
