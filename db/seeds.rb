# frozen_string_literal: true

# rails db:seed
LocSubject.delete_all
LocSubject.load_from_file('lib/loc_subjects.txt')

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

AppSettings.app_maintenance = true

AppSettings.app_maintenance_message = <<HEREDOC
<div><strong>Attention:</strong> maintenance shutdown soon.</div>
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

{{application_url | replace: "http://etd", "https://etd"}}

Sincerely,
Faculty of Graduate Studies
HEREDOC

AppSettings.email_status_change_allow = true

AppSettings.email_status_change_subject = <<HEREDOC
The status of your thesis has been changed.
HEREDOC

AppSettings.email_status_change_body = <<HEREDOC
Hi {{student_name}}

{{status_message}}

{{custom_message}}



Click on the url below to login to review your thesis status.

You will need your Passport York I.D. to log in.

{{application_url | replace: "http://etd", "https://etd"}}

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
<div>Welcome to York University’s Electronic Thesis and Dissertation (ETD) application. This interface will enable you to upload and submit your final approved thesis or dissertation to the Graduate Milestones and Progression Coordinator in the Faculty of Graduate Studies.<br><br></div><div>Once your submission is approved and all requirements for graduation are met, your thesis or dissertation will be submitted to YorkSpace, York University's digital library of research outputs and will be available for electronic viewing through Library and Archives Canada after it has been added to YorkSpace.<br><br></div><div>For step-by-step submission instructions and more information on ETD, <a href="https://www.yorku.ca/gradstudies/students/current-students/thesis-and-dissertation/">please visit FGS’s website.<br></a><br></div>
HEREDOC

AppSettings.student_begin_external_non_yorku_email = <<HEREDOC
<div>Please provide a secondary email address for future contact. Please note that this needs to be a non-York email address, in the event that your York email address is deactivated after your completion.<br><br></div>
HEREDOC

AppSettings.student_update_details_initial = <<HEREDOC

HEREDOC

AppSettings.student_update_details_abstract = <<HEREDOC
<div>Add an abstract for your submission. The abstract is typically a 150 to 250- word paragraph that provides a short summary of your research, including a summary of the problem or issue, a description of the research method and design, the major findings and the conclusion. Your abstract should include important key words that describe your research and research methodology, as these words will support discoverability of your research in search engines and research databases.<br><br></div>
HEREDOC

AppSettings.student_update_details_subjects = <<HEREDOC
<div>You will be asked to select at least one subject heading from a drop-down menu that will be attributed to your thesis depending on your discipline. These terms are drawn from the Library of Congress subject headings and align with the degree names issued by the University. These terms relate to your area of study.<br><br></div>
HEREDOC

AppSettings.student_update_details_keywords = <<HEREDOC
<div>Choose up to ten key words or phrases that describe what your work is about. The keywords should repeat core concepts in your abstract. Capitalize each keyword or the first word of a keyword phrase and separate words or terms with commas. Select terms that your target audience might use when searching for your work. Keep in mind that:<br><br></div><ul><li>Terms that are too broad (e.g. 'Anthropology') or too narrow (e.g. 'fM space') may not help people find your work.</li><li>There is no need to add your subject terms as keywords.&nbsp;</li><li>Use the plural form of nouns (e.g., 'magazines' instead of 'magazine').&nbsp;</li><li>Adding variations or synonyms for key words can be helpful for searchers but avoid common variations (e.g. employees or workers).&nbsp;</li></ul>
HEREDOC

AppSettings.student_upload_files = <<HEREDOC
<div>You will need to upload the following files:<br><br></div><ul><li><strong>Primary file (thesis/dissertation):</strong> Before uploading your thesis or dissertation, you will need to save it as a PDF file (.pdf), which must be compatible with Adobe Acrobat version 5.0 or higher&nbsp;</li><li><strong>If needed, supplementary files:</strong> Supplementary files refer to items that are part of the approved thesis/dissertation that cannot be included in the PDF document (thesis/dissertation). Examples of these files include multi–media, sound, video or hypertext. A supplementary file is NOT an appendix. Regular appendices can be included in the PDF document of your thesis/dissertation.</li><li>YorkSpace can accept a variety of file types. The file size should not exceed 4 GB. If you need to deposit larger files, contact <a href="mailto:diginit@yorku.ca">diginit@yorku.ca</a> for a consultation. Please see the Library’s <a href="https://www.library.yorku.ca/web/about-us/library-policies/digital-preservation-policy/preservation-action-plan-theses/">Preservation Action Plan – Theses</a> for recommended file formats.&nbsp;</li></ul>
HEREDOC

AppSettings.student_primary_upload_files = <<HEREDOC
<p>Before uploading your thesis or dissertation, you will need to save it as a PDF file (.pdf), which must be compatible with Adobe Acrobat version 5.0 or higher.</p>
HEREDOC

AppSettings.student_supplementary_upload_files = <<HEREDOC
<div>For preservation purposes, we recommend that supplementary files be in these formats to enable migration to new formats when a file format becomes obsolete:<br><br></div><ul><li><strong>Documents:</strong> Portable Document Format (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods).&nbsp;</li><li><strong>Images:</strong> Tagged Image File format (.tif)</li><li><strong>Data:</strong> Comma-separated values (.csv) or other delimited text, Extensible Markup Language (.xml)</li><li><strong>Video:</strong> MPEG-4 (.mp4) files are preferred, but we can also accept AVI (.avi) and MOV (.mov) file formats.</li><li><strong>Audio:</strong> MPEG-1 Audio Layer 3 (.mp3) file are preferred, but we can also accept Free Lossless Audio Codec (.flac) or WAVE (.wav) file formats.</li></ul><div>Please ensure that:&nbsp;</div><ul><li>You have permission from subjects appearing in media files.&nbsp;</li><li>The total size of your supplementary files does not exceed 4 gigabytes (4GB)</li><li>If you wish to upload a type of file that you do not see on this list, please email diginit@yorku.ca for support.</li></ul>
HEREDOC

AppSettings.student_supplementary_licence_upload_files = <<HEREDOC
<div>Only PDF files allowed.</div>
HEREDOC

AppSettings.student_supplementary_embargo_upload_files = <<HEREDOC
<div>Please Upload the following documents:<br><br></div><ul><li><strong>Supervisor Letter</strong></li><li><strong>Other Embargo Supporting Documents</strong></li><li><strong>Portable Document Format:</strong> (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods).</li></ul>
HEREDOC

AppSettings.student_review_license_info = <<HEREDOC
<div>By signing these non-exclusive distribution licences, you are confirming that:<br><br></div><ul><li>your dissertation is your original work;&nbsp;</li><li>that your dissertation does not infringe any rights of others;&nbsp;</li><li>and that as the copyright holder, you have the right to grant a non-exclusive distribution licence to York University, YorkSpace (the university’s institutional repository), and Library and Archives Canada (LAC).&nbsp;</li></ul><div>This allows York University and LAC to make copies, including electronically formatted copies, and/or distribute worldwide all or part of the dissertation, subject to the conditions outlined in the licences.<br><br></div><div>If applicable, you should submit copies of any required copyright permissions before the final dissertation submission to the Office of the Dean, Graduate Studies. You should also retain copies of all copyright permission requests and approvals.<br><br></div>
HEREDOC

AppSettings.student_review_license_lac = <<HEREDOC

HEREDOC

AppSettings.student_review_lac_licence_instructions = <<HEREDOC
<p>Please upload your completed Library and Archives Canada Licence document.</p><p> French or English versions of the licence form can be downloaded from the <a href='https://www.yorku.ca/gradstudies/students/current-students/registration-enrolment/fgs-forms/#copyright' target='_blank'>Faculty of Graduate Studies’ Forms website.</a> </p>
HEREDOC

AppSettings.student_review_license_yorkspace = <<HEREDOC
<pre>YORKSPACE NON-EXCLUSIVE DISTRIBUTION LICENCE

By signing and submitting this licence, you (the author(s) or copyright
owner) grant to York University the non-exclusive right to reproduce,
translate (as defined below), and/or distribute your submission (including
the abstract) worldwide in print and electronic format and in any medium,
including but not limited to audio or video.

YorkSpace and your use of YorkSpace is governed by the terms and conditions of
the York University website posted at:
http://www.yorku.ca/web/about_yorku/privacy.html

You agree that York University may, without changing the content, translate the
submission to any medium or format for the purpose of preservation.

You also agree that York University may keep more than one copy of this submission for
purposes of security, back-up and preservation.

You represent that the submission is your original work, and that you have
the right to grant the rights contained in this licence. You also represent
that your submission does not, to the best of your knowledge, infringe upon
anyone's copyright.

If the submission contains material for which you do not hold copyright,
you represent that you have obtained the unrestricted permission of the
copyright owner to grant York University the rights required by this licence, and that
such third-party owned material is clearly identified and acknowledged
within the text or content of the submission.

IF THE SUBMISSION IS BASED UPON WORK THAT HAS BEEN SPONSORED OR SUPPORTED
BY AN AGENCY OR ORGANIZATION OTHER THAN YORK UNIVERSITY, YOU REPRESENT THAT YOU HAVE
FULFILLED ANY RIGHT OF REVIEW OR OTHER OBLIGATIONS REQUIRED BY SUCH
CONTRACT OR AGREEMENT.

York University will clearly identify your name(s) as the author(s) or owner(s) of the
submission, and will not make any alteration, other than as allowed by this
licence, to your submission.
<br></pre>
HEREDOC

AppSettings.student_review_license_etd = <<HEREDOC
<pre>Non-Exclusive License to York University

In the interests of facilitating research and contributing to scholarship at York University (“York”) and elsewhere, the author (“Author”) hereby grants to York a non-exclusive, royalty free and irrevocable license on the following terms:

- York is permitted to reproduce, copy, store, archive, distribute, translate, publish and loan  to the public the Author’s thesis or dissertation, including the abstract and metadata  (“the Work”), in whole or in part, anywhere in the world, for non-commercial purposes, in any format and in any medium.  Distribution may be in any form, including, but not limited to, the right to transmit or publish the Work through the Internet or any other telecommunications device; to digitize, photocopy and microfiche the Work; or through library, interlibrary and public loans.  York is permitted to sub-license or assign any of the rights mentioned in this agreement to third party agents to act on York's behalf.

- York may keep more than one copy of the Work and convert the Work from its original format into any medium or format for the purposes of security, back-up, and preservation or to facilitate the exercise of York’s rights under this license.

- York may collect cost-recovery fees for reproducing or otherwise making the Work available.

- The Author confirms that the Work is the approved and final version, in whole and without alteration, submitted to the Faculty of Graduate Studies, York University, as a requirement of the York degree program. 

- The Author confirms that the Work is their original work, that they have the right and authority to grant the rights set out in this license and that the Work does not infringe copyright or other intellectual property rights of any other person or institution.  If the Work contains material to which the Author does not hold copyright it is clearly identified and acknowledged. Copyright–protected material not in the public domain is included either under the "fair dealing" provisions of the Copyright Act (Canada) or the Author has obtained and retained copies of written permission from the copyright holder(s) to include the material and to grant to York the rights set out in this license.

- York will clearly identify the Author as the copyright holder of the Work and will not make any alteration, other than as allowed by this license, to the Work. All copies of the Work will include a statement to the effect that the copy is being made available in this form by authority of the Author and copyright owner solely for the purpose of private study and research and may not be copied, further distributed or altered for any purpose, except as permitted by copyright law, without written authority from the Author.

- A nonexclusive license in no way limits the Author as the copyright holder in making other nonexclusive uses of the Work. The Author otherwise retains all rights in the Work subject to the nonexclusive grants and conditions of this license and accordingly holds sole responsibility for complying with copyright and other legal requirements.

- The Author agrees that York is not responsible for any misuse of the Work by third parties who access the Work through YorkSpace, York's Institutional Repository.

- I have reviewed and agree to accept the conditions and regulations of the Faculty of Graduate Studies as outlined in the Thesis and Dissertation Handbook.
<br></pre>
HEREDOC

AppSettings.student_review_details = <<HEREDOC

HEREDOC

AppSettings.student_submit_for_review = <<HEREDOC
<div>Please review the uploaded files and information below and confirm that everything is accurate, before you click the 'Submit for review' button.<br><br></div>
HEREDOC

AppSettings.student_check_status_description = <<HEREDOC

HEREDOC

AppSettings.student_check_status_open = <<HEREDOC
<div>A record has been created for you to submit your thesis/dissertation. As long as the status is Open, you may continue to make changes until you are ready to submit.<br><br></div>
HEREDOC

AppSettings.student_check_status_under_review = <<HEREDOC
<div>Your submission has been received and is being reviewed by a Milestones and Progression Coordinator in the Faculty of Graduate Studies. If you need to re-open your ETD record to make any changes, <a href="https://www.yorku.ca/gradstudies/contact/fgs-staff-directory/">please visit the following page</a> to identify and contact the coordinator who supports your program.<br><br></div>
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
<div>Current status Rejected.<br><br></div>
HEREDOC

AppSettings.primary_thesis_file_extensions = <<HEREDOC
.pdf
HEREDOC

AppSettings.supplemental_thesis_file_extensions = <<HEREDOC
.pdf, .doc, .docx, .txt, .html, .htm, .odt, .odp, .ods, .png, .tif, .jpg, .csv, .xml, .avi, .flac, .wav, .mp3, .mp4, .mov, .xlsx
HEREDOC

AppSettings.licence_file_extensions = <<HEREDOC
.pdf
HEREDOC

AppSettings.embargo_file_extensions = <<HEREDOC
.pdf, .txt, .html, .htm, .odt, .odp, .ods
HEREDOC


