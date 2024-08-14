
## HELPERS FOR SYSTEM TESTS
module SystemTestHelper

  ## Chosen Js Plugin selector
  def select_chosen_option(dropdown_selector, option_text)
    select_element = find(dropdown_selector)
    select_element.click
    within "#{dropdown_selector} .chosen-results" do
       find('li', text: option_text).click
    end
    assert_selector "#{dropdown_selector} .chosen-single", text: option_text
  end

  def wait_for_download(filename)
    loop do
      break if File.exist?(filename)
      sleep 1
    end
  end
end
