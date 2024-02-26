namespace :get_document do
    task names: :environment do
        d = Document.includes(:thesis).where(thesis: {embargoed: false, status: 'published'}, deleted:false)
        content = ""
        d.each do |doc|
            content << File.basename(doc.file.to_s) + "\n"
        end
        File.open("document_names.txt", 'w') { |file| file.write(content) }
        puts "File document_names.txt generated"
    end
end
