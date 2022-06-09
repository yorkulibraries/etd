module CommitteeMembersHelper
  
  def sort_by_last_name(list, double=true)
    return Array.new if list.blank?
    
    sorted = Array.new
    list.each do |member|
      names = member.strip.rpartition(" ")

      sorted.push ["#{names.last}, #{names.first}", "#{member}"] if double
      sorted.push "#{names.first} #{names.last}" unless double
    end
    
    sorted.sort
  end
end
