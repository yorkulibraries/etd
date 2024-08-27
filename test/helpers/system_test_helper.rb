
## HELPERS FOR SYSTEM TESTS
module SystemTestHelper
  def wait_for_download(filename, timeout=10)
    Timeout.timeout(timeout) do
      sleep 0.1 until File.exist?(filename)
    end
  end
end
