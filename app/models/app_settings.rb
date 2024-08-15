# frozen_string_literal: true

# RailsSettings Model
class AppSettings < RailsSettings::Base
  cache_prefix { 'v1' }

  field :app_name, default: ENV['app_name'] || 'ETD'
  field :app_owner, default: ENV['app_owner'] || 'York University Libraries'
  field :app_maintenance, default: ENV['app_maintenance'] || false
  field :app_maintenance_message,
        default: ENV['app_maintenance_message'] || 'ETD Application will be taken down for maintenance today from 12pm to 1pm.  We apologize for any inconvenience this may have caused.'
  field :email_allow, default: ENV['email_allow'] || true
  field :email_from, default: ENV['email_from'] || 'noreply@yorku.ca'
  field :email_welcome_subject,
        default: ENV['email_welcome_subject'] || "Welcome to York University's Electronic Thesis and Dissertation (ETD) application"
  field :email_welcome_allow, default: ENV['email_welcome_allow'] || true
  field :email_welcome_body, default: ENV['email_welcome_body'] || 'Email body'
  field :email_status_change_allow, default: ENV['email_status_change_allow'] || true
  field :email_status_change_subject,
        default: ENV['email_status_change_subject'] || 'The status of your thesis has been changed.'
  field :email_status_change_body, default: ENV['email_status_change_body'] || 'Status Change email text goes here'
  field :errors_email_subject_prefix, default: ENV['errors_email_subject_prefix'] || '[ETD Error] '
  field :errors_email_from,
        default: ENV['errors_email_from'] || "'ETD Notifier' <etd-errors@your-instituttion.website>"
  field :errors_email_to, default: ENV['errors_email_to'] || 'your.email@your-instituttion.email'
  field :dspace_live_username, default: ENV['dspace_live_username'] || ''
  field :dspace_live_password, default: ENV['dspace_live_password'] || ''
  field :dspace_live_service_document_url, default: ENV['dspace_live_service_document_url'] || ''
  field :dspace_live_collection_uri, default: ENV['dspace_live_collection_uri'] || ''
  field :dspace_live_collection_title, default: ENV['dspace_live_collection_title'] || ''
  field :student_begin_submission, default: "
  <p>Welcome to York University’s Electronic Thesis and Dissertation (ETD) application. This interface will enable you to upload and submit your final approved thesis or dissertation to the Graduate Milestones and Progression Coordinator in the Faculty of Graduate Studies. </p>

  <p>Once your submission is approved and all requirements for graduation are met, your thesis or dissertation will be submitted to YorkSpace, York University's digital library of research outputs and will be available for electronic viewing through Library and Archives Canada after it has been added to YorkSpace. </p>

  <p>For step-by-step submission instructions and more information on ETD, please visit FGS\’s website. At any point while you are using the application, you may click on the help button next to each field for more information. </p>"
  field :student_begin_external_non_yorku_email, default: "Please provide a secondary email address for future contact. Please note that this needs to be a non-York email address, in the event that your York email address is deactivated after your completion."
  field :student_update_details_initial, default: ""
  field :student_update_details_abstract, default: "<p>Add an abstract for your submission. The abstract is typically a 150 to 250- word paragraph that provides a short summary of your research, including a summary of the problem or issue, a description of the research method and design, the major findings and the conclusion. Your abstract should include important key words that describe your research and research methodology, as these words will support discoverability of your research in search engines and research databases. </p>"
  field :student_update_details_subjects, default: "<p>You will be asked to select at least one subject heading from a drop-down menu that will be attributed to your thesis depending on your discipline. These terms are drawn from the Library of Congress subject headings and align with the degree names issued by the University. These terms relate to your area of study. </p>"
  field :student_update_details_keywords, default: "<p>
  Choose up to ten key words or phrases that describe what your work is about. The keywords should repeat core concepts in your abstract. Capitalize each keyword or the first word of a keyword phrase and separate words or terms with commas. Select terms that your target audience might use when searching for your work. Keep in mind that: 
  <ul>
   <li>Terms that are too broad (e.g. 'Anthropology') or too narrow (e.g. 'fM space') may not help people find your work.</li>
   <li>There is no need to add your subject terms as keywords. </li>
   <li>Use the plural form of nouns (e.g., 'magazines' instead of 'magazine'). </li>
   <li>Adding variations or synonyms for key words can be helpful for searchers but avoid common variations (e.g. employees or workers). </li>
  </ul>
  </p>"
  field :student_upload_files, default: "<p>You will need to upload the following files: 
  <ul>
    <li><strong>Primary file (thesis/ dissertation):</strong>  Before uploading your thesis or dissertation, you will need to save it as a PDF file (.pdf), which must be compatible with Adobe Acrobat version 5.0 or higher  </li><br/>
    <li><strong>If needed, supplementary files:</strong> Supplementary files refer to items that are part of the approved thesis/dissertation that cannot be included in the PDF document (thesis/dissertation). Examples of these files include multi–media, sound, video or hypertext. A supplementary file is NOT an appendix. Regular appendices can be included in the PDF document of your thesis/dissertation.</li><br/>
    <li>YorkSpace can accept a variety of file types. The file size should not exceed 4 GB. If you need to deposit larger files, contact <a href='mailto:diginit@yorku.ca'>diginit@yorku.ca</a> for a consultation. Please see the Library’s <a href='https://www.library.yorku.ca/web/about-us/library-policies/digital-preservation-policy/preservation-action-plan-theses/'>Preservation Action Plan – Theses</a> for recommended file formats. </li>
  </ul> </p>"
  field :student_supplementary_upload_files, default: "
  <p>For preservation purposes, we recommend that supplementary files be in these formats to enable migration to new formats when a file format becomes obsolete: </p>
  <ul>
  <li><strong>Documents:</strong> Portable Document Format (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods). </li>
  <li><strong>Images:</strong> Tagged Image File format (.tif)</li>
  <li><strong>Data:</strong> Comma-separated values (.csv) or other delimited text, Extensible Markup Language (.xml)</li>
  <li><strong>Video:</strong> MPEG-4 (.mp4) files are preferred, but we can also accept AVI (.avi) and MOV (.mov) file formats.</li>
  <li><strong>Audio:</strong> MPEG-1 Audio Layer 3 (.mp3) file are preferred, but we can also accept Free Lossless Audio Codec (.flac) or WAVE (.wav) file formats.</li>
  </ul>
  <p>Please ensure that: 
  <ul>
  <li>You have permission from subjects appearing in media files. </li>
  <li>The total size of your supplementary files does not exceed 4 gigabytes (4GB)</li> 
  <li>If you wish to upload a type of file that you do not see on this list, please email diginit@yorku.ca for support.</li> </p>"
  field :student_supplementary_embargo_upload_files, default: "<p> Please Upload the following documents:</p> 
  <ul>
  <li><strong>Supervisor Letter</strong></li>
  <li><strong>Other Embargo Supporting Documents</strong></li>
  <li><strong>Portable Document Format:</strong> (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods).</li>
  </ul>"
  field :student_review_license_info, default: "<p>By signing these non-exclusive distribution licences, you are confirming that: 
  <ul>
    <li>your dissertation is your original work; </li>
    <li>that your dissertation does not infringe any rights of others; </li>
    <li>and that as the copyright holder, you have the right to grant a non-exclusive distribution licence to York University, YorkSpace (the university’s institutional repository), and Library and Archives Canada (LAC). </li>
  </ul>
  <p>This allows York University and LAC to make copies, including electronically formatted copies, and/or distribute worldwide all or part of the dissertation, subject to the conditions outlined in the licences. </p>
  <p>If applicable, you should submit copies of any required copyright permissions before the final dissertation submission to the Office of the Dean, Graduate Studies. You should also retain copies of all copyright permission requests and approvals.</p>"
  field :student_review_license_lac, default: ""
  field :student_review_lac_licence_instructions, default: "<p>Please upload your completed Library and Archives Canada License document.</p><p> French or English versions of the license form can be downloaded from the <a href='https://www.yorku.ca/gradstudies/students/current-students/registration-enrolment/fgs-forms/#copyright'>Faculty of Graduate Studies’ Forms website.</a> </p>"
  field :student_review_license_yorkspace, default: ""
  field :student_review_license_etd, default: ""
  field :student_review_details, default: ""
  field :student_submit_for_review, default: "<p>Please review the uploaded files and information below and confirm that everything is accurate, before you click the 'Submit for review' button. </p>"
  field :student_check_status_description, default: ""
  field :student_check_status_open, default: "A record has been created for you to submit your thesis/dissertation. As long as the status is Open, you may continue to make changes until you are ready to submit."
  field :student_check_status_under_review, default: "<p>Your submission has been received and is being reviewed by a Milestones and Progression Coordinator in the Faculty of Graduate Studies. If you need to re-open your ETD record to make any changes, <a href='https://www.yorku.ca/gradstudies/contact/fgs-staff-directory/'>please visit the following page</a> to identify and contact the coordinator who supports your program. </p>"
  field :student_check_status_returned, default: "<p>Your submission has been reviewed by a Thesis Coordinator and has been returned to you for modification. Please make the updates detailed in the email from the Thesis Coordinator, attach an updated PDF (if applicable) and resubmit.</p>"
  field :student_check_status_accepted, default: "<p>Your submission has been accepted and will be published following conferral of your degree.</p>"
  field :student_check_status_published, default: "<p>Your thesis/dissertation has been deposited in YorkSpace, York University's open access institutional repository. It is available in <a href='https://hdl.handle.net/10315/26310'>the Faculty of Graduate Studies' collection of Electronic Theses and Dissertations.</a> It will soon be visible in systems like <a href='https://scholar.google.com/'>Google Scholar</a> and will eventually be available through the <a href='https://library-archives.canada.ca/eng/services/services-libraries/theses/Pages/theses-canada.aspx'>online, national collection at Library and Archives Canada.</a></p>"
  field :student_check_status_rejected, default: "Current status Rejected."
end
