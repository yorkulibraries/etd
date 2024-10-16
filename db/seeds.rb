# frozen_string_literal: true

# rails db:seed
LocSubject.load_from_file('lib/loc_subjects.txt') if (Rails.env != 'test') && LocSubject.all.count.zero?

if (Rails.env != 'test') && User.all.count.zero?
  [User::ADMIN, User::MANAGER, User::STAFF].each do |role|
    user = User.new
    user.username = role.to_s
    user.email = "#{role}@me.ca"
    user.name = "#{role} User"
    user.role = role
    user.blocked = false
    user.save
  end
end

if (Rails.env == 'development') && GemRecord.all.count.zero?
  (1..2).each do |i|
    g = GemRecord.create(
      studentname: "studentname #{i}",
      sisid: "69420000#{i}",
      emailaddress: "student-email#{i}@domain.com",
      eventtype: GemRecord::PHD_EXAM,
      eventdate: 45.days.ago.to_s,
      examresult: 'Accepted Pending Specified Revisions',
      title: "title #{i}",
      program: "GS PHD MATS - Faculty of Graduate Studies, Ph.D., Mathematics & Statistic",
      superv: "superv #{i}", 
      seqgradevent: "#{i}".to_i,
      examdate: 45.days.ago.to_s
    )
    g.save!

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "John #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::CHAIR
    cm.save

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "Jane #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::COMMITTEE_MEMBER
    cm.save
  end

  (3..4).each do |i|
    g = GemRecord.create(
      studentname: "studentname #{i}",
      sisid: "69420000#{i}",
      emailaddress: "student-email#{i}@domain.com",
      eventtype: GemRecord::MASTERS_EXAM,
      eventdate: 45.days.ago.to_s,
      examresult: 'Accepted Pending Specified Revisions',
      title: "title #{i}",
      program: "GS MSC KAHS - Faculty Of Graduate Studies, M.Sc., Kinesiology & Health Science",
      superv: "superv #{i}", 
      seqgradevent: "#{i}".to_i,
      examdate: 45.days.ago.to_s
    )
    g.save!

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "John #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::CHAIR
    cm.save

    cm = CommitteeMember.new
    cm.gem_record = g
    cm.first_name = "Jane #{i}"
    cm.last_name = "Doe"
    cm.role = CommitteeMember::COMMITTEE_MEMBER
    cm.save
  end
end


#######################################
## seed settings
#######################################


AppSettings.app_name = <<HEREDOC
ETD
HEREDOC

AppSettings.app_owner = <<HEREDOC
York University Libraries
HEREDOC

AppSettings.app_maintenance = false

AppSettings.app_maintenance_message = <<HEREDOC
ETD Application will be taken down for maintenance tomorrow (May 13) from 7am to 8am.  We apologize for any inconvenience this may have caused.
HEREDOC

AppSettings.email_allow = true

AppSettings.email_from = <<HEREDOC
noreply@yorku.ca
HEREDOC

AppSettings.email_welcome_subject = <<HEREDOC
Welcome to York University's Electronic Thesis and Dissertation (ETD) application
HEREDOC

AppSettings.email_welcome_allow = true

AppSettings.email_welcome_body = <<HEREDOC
Dear {{student_name}},
 
Congratulations on successfully defending your thesis or dissertation!

Following your successful oral exam, submission of the thesis/dissertation to the Faculty of Graduate Studies is a requirement for graduation and convocation.

Please click on the following link, which will take you to York University’s Electronic Thesis and Dissertation (ETD) application. This interface will enable you to upload and submit your final approved thesis/dissertation to the Faculty of Graduate Studies.

You will need your Passport York I.D. to log in.

Click on the url below to begin.

https://etd.library.yorku.ca


Sincerely,
Faculty of Graduate Studies
HEREDOC

AppSettings.email_status_change_allow = <<HEREDOC
true
HEREDOC

AppSettings.email_status_change_subject = <<HEREDOC
The status of your thesis has been changed.
HEREDOC

AppSettings.email_status_change_body = <<HEREDOC
Hi {{student_name}}

{{status_message}}

{{custom_message}}



Click on the url below to login to review your thesis status.

You will need your Passport York I.D. to log in.

https://etd.library.yorku.ca

Sincerely,
Faculty of Graduate Studies
HEREDOC

AppSettings.errors_email_subject_prefix = <<HEREDOC
[ETD Error] 
HEREDOC

AppSettings.errors_email_from = <<HEREDOC
noreply@yorku.ca
HEREDOC

AppSettings.errors_email_to = <<HEREDOC

HEREDOC

AppSettings.dspace_live_username = <<HEREDOC

HEREDOC

AppSettings.dspace_live_password = <<HEREDOC

HEREDOC

AppSettings.dspace_live_service_document_url = <<HEREDOC

HEREDOC

AppSettings.dspace_live_collection_uri = <<HEREDOC

HEREDOC

AppSettings.dspace_live_collection_title = <<HEREDOC

HEREDOC

AppSettings.student_begin_submission = <<HEREDOC
<div>Welcome to York University’s Electronic Thesis and Dissertation (ETD) application. This interface will enable you to upload and submit your final approved thesis or dissertation to the Graduate Milestones and Progression Coordinator in the Faculty of Graduate Studies.&nbsp;<br><br></div><div>Once your submission is approved and all requirements for graduation are met, your thesis or dissertation will be submitted to YorkSpace, York University's digital library of research outputs and will be available for electronic viewing through Library and Archives Canada after it has been added to YorkSpace.&nbsp;<br><br></div><div>For step-by-step submission instructions and more information on ETD, <a href="https://www.yorku.ca/gradstudies/students/current-students/thesis-and-dissertation/">please visit FGS’s website.<br></a><br></div>
HEREDOC

AppSettings.student_begin_external_non_yorku_email = <<HEREDOC
Please provide a secondary email address for future contact. Please note that this needs to be a non-York email address, in the event that your York email address is deactivated after your completion.
HEREDOC

AppSettings.student_update_details_initial = <<HEREDOC

HEREDOC

AppSettings.student_update_details_abstract = <<HEREDOC
<p>Add an abstract for your submission. The abstract is typically a 150 to 250- word paragraph that provides a short summary of your research, including a summary of the problem or issue, a description of the research method and design, the major findings and the conclusion. Your abstract should include important key words that describe your research and research methodology, as these words will support discoverability of your research in search engines and research databases. </p>
HEREDOC

AppSettings.student_update_details_subjects = <<HEREDOC
<p>You will be asked to select at least one subject heading from a drop-down menu that will be attributed to your thesis depending on your discipline. These terms are drawn from the Library of Congress subject headings and align with the degree names issued by the University. These terms relate to your area of study. </p>
HEREDOC

AppSettings.student_update_details_keywords = <<HEREDOC
<p>
  Choose up to ten key words or phrases that describe what your work is about. The keywords should repeat core concepts in your abstract. Capitalize each keyword or the first word of a keyword phrase and separate words or terms with commas. Select terms that your target audience might use when searching for your work. Keep in mind that: 
  <ul>
   <li>Terms that are too broad (e.g. 'Anthropology') or too narrow (e.g. 'fM space') may not help people find your work.</li>
   <li>There is no need to add your subject terms as keywords. </li>
   <li>Use the plural form of nouns (e.g., 'magazines' instead of 'magazine'). </li>
   <li>Adding variations or synonyms for key words can be helpful for searchers but avoid common variations (e.g. employees or workers). </li>
  </ul>
  </p>
HEREDOC

AppSettings.student_upload_files = <<HEREDOC
<div>You will need to upload the following files:&nbsp;<br><br></div><ul><li><strong>Primary file (thesis/dissertation):</strong> Before uploading your thesis or dissertation, you will need to save it as a PDF file (.pdf), which must be compatible with Adobe Acrobat version 5.0 or higher&nbsp;</li></ul><div><br><br></div><ul><li><strong>If needed, supplementary files:</strong> Supplementary files refer to items that are part of the approved thesis/dissertation that cannot be included in the PDF document (thesis/dissertation). Examples of these files include multi–media, sound, video or hypertext. A supplementary file is NOT an appendix. Regular appendices can be included in the PDF document of your thesis/dissertation.</li></ul><div><br><br></div><ul><li>YorkSpace can accept a variety of file types. The file size should not exceed 4 GB. If you need to deposit larger files, contact <a href="mailto:diginit@yorku.ca">diginit@yorku.ca</a> for a consultation. Please see the Library’s <a href="https://www.library.yorku.ca/web/about-us/library-policies/digital-preservation-policy/preservation-action-plan-theses/">Preservation Action Plan – Theses</a> for recommended file formats.&nbsp;</li></ul>
HEREDOC

AppSettings.student_primary_upload_files = <<HEREDOC
<p>Before uploading your thesis or dissertation, you will need to save it as a PDF file (.pdf), which must be compatible with Adobe Acrobat version 5.0 or higher.</p>
HEREDOC

AppSettings.student_supplementary_upload_files = <<HEREDOC
<div>For preservation purposes, we recommend that supplementary files be in these formats to enable migration to new formats when a file format becomes obsolete:&nbsp;<br><br></div><ul><li><strong>Documents:</strong> Portable Document Format (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods).&nbsp;</li><li><strong>Images:</strong> Tagged Image File format (.tif)</li><li><strong>Data:</strong> Comma-separated values (.csv) or other delimited text, Extensible Markup Language (.xml)</li><li><strong>Video:</strong> MPEG-4 (.mp4) files are preferred, but we can also accept AVI (.avi) and MOV (.mov) file formats.</li><li><strong>Audio:</strong> MPEG-1 Audio Layer 3 (.mp3) file are preferred, but we can also accept Free Lossless Audio Codec (.flac) or WAVE (.wav) file formats.</li></ul><div>Please ensure that:&nbsp;<br><br></div><ul><li>You have permission from subjects appearing in media files.&nbsp;</li><li>The total size of your supplementary files does not exceed 4 gigabytes (4GB)</li><li>If you wish to upload a type of file that you do not see on this list, please email diginit@yorku.ca for support.</li></ul>
HEREDOC

AppSettings.student_supplementary_embargo_upload_files = <<HEREDOC
<div>&nbsp;Please Upload the following documents:<br><br></div><ul><li><strong>Supervisor Letter</strong></li><li><strong>Other Embargo Supporting Documents</strong></li><li><strong>Portable Document Format:</strong> (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods).</li></ul>
HEREDOC

AppSettings.student_review_license_info = <<HEREDOC
<div>By signing these non-exclusive distribution licences, you are confirming that:&nbsp;<br><br></div><ul><li>your dissertation is your original work;&nbsp;</li><li>that your dissertation does not infringe any rights of others;&nbsp;</li><li>and that as the copyright holder, you have the right to grant a non-exclusive distribution licence to York University, YorkSpace (the university’s institutional repository), and Library and Archives Canada (LAC).&nbsp;</li></ul><div>This allows York University and LAC to make copies, including electronically formatted copies, and/or distribute worldwide all or part of the dissertation, subject to the conditions outlined in the licences.&nbsp;<br><br></div><div>If applicable, you should submit copies of any required copyright permissions before the final dissertation submission to the Office of the Dean, Graduate Studies. You should also retain copies of all copyright permission requests and approvals.<br><br></div>
HEREDOC

AppSettings.student_review_license_lac = <<HEREDOC

HEREDOC

AppSettings.student_review_lac_licence_instructions = <<HEREDOC
<p>Please upload your completed Library and Archives Canada Licence document.</p><p> French or English versions of the licence form can be downloaded from the <a href='https://www.yorku.ca/gradstudies/students/current-students/registration-enrolment/fgs-forms/#copyright' target='_blank'>Faculty of Graduate Studies’ Forms website.</a> </p>
HEREDOC

AppSettings.student_review_license_yorkspace = <<HEREDOC
<div>YorkSpace Non-Exclusive Distribution Licence&nbsp;</div>
HEREDOC

AppSettings.student_review_license_etd = <<HEREDOC
<div>YorkU ETD Licence</div>
HEREDOC

AppSettings.student_review_details = <<HEREDOC

HEREDOC

AppSettings.student_submit_for_review = <<HEREDOC
<div>Please review the uploaded files and information below and confirm that everything is accurate, before you click the 'Submit for review' button.&nbsp;<br><br></div>
HEREDOC

AppSettings.student_check_status_description = <<HEREDOC

HEREDOC

AppSettings.student_check_status_open = <<HEREDOC
<div>A record has been created for you to submit your thesis/dissertation. As long as the status is Open, you may continue to make changes until you are ready to submit.</div>
HEREDOC

AppSettings.student_check_status_under_review = <<HEREDOC
<div>Your submission has been received and is being reviewed by a Milestones and Progression Coordinator in the Faculty of Graduate Studies. If you need to re-open your ETD record to make any changes, <a href="https://www.yorku.ca/gradstudies/contact/fgs-staff-directory/">please visit the following page</a> to identify and contact the coordinator who supports your program.&nbsp;<br><br></div>
HEREDOC

AppSettings.student_check_status_returned = <<HEREDOC
<div>Your submission has been reviewed by a Thesis Coordinator and has been returned to you for modification. Please make the updates detailed in the email from the Thesis Coordinator, attach an updated PDF (if applicable) and resubmit.<br><br></div>
HEREDOC

AppSettings.student_check_status_accepted = <<HEREDOC
<div>Your submission has been accepted and will be published following conferral of your degree.<br><br></div>
HEREDOC

AppSettings.student_check_status_published = <<HEREDOC
<div>Your thesis/dissertation has been deposited in YorkSpace, York University's open access institutional repository. It is available in <a href="https://hdl.handle.net/10315/26310">the Faculty of Graduate Studies' collection of Electronic Theses and Dissertations.</a> It will soon be visible in systems like <a href="https://scholar.google.com/">Google Scholar</a> and will eventually be available through the <a href="https://library-archives.canada.ca/eng/services/services-libraries/theses/Pages/theses-canada.aspx">online, national collection at Library and Archives Canada.<br></a><br></div>
HEREDOC

AppSettings.student_check_status_rejected = <<HEREDOC
<div>Current status Rejected.</div>
HEREDOC
