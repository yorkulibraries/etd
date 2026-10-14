# frozen_string_literal: true

class DocumentDownloadsController < ApplicationController
  def show
    student = Student.find(params[:student_id])
    thesis = student.theses.find(params[:thesis_id])
    # Reading an owned thesis is allowed after submission; edit rules are untouched.
    authorize! :show, thesis
    document = thesis.documents.not_deleted.find_by(id: params[:id])
    path = safe_file_path(document)
    unless path
      render plain: 'This file is unavailable. Contact FGS for help.', status: :not_found
      return
    end

    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('X-Content-Type-Options', 'nosniff')
    send_file path, filename: File.basename(document.file.identifier),
                   type: 'application/octet-stream', disposition: 'attachment'
  end

  private

  def safe_file_path(document)
    return unless document&.file&.path.present? && File.file?(document.file.path) && File.readable?(document.file.path)

    root = Pathname.new(document.file.root).realpath
    directory = root.join(document.file.store_dir).expand_path
    path = Pathname.new(document.file.path).realpath
    # A symlink or edited file identifier must not escape this document's directory.
    return unless directory.to_s.start_with?("#{root}/uploads/") &&
                  path.to_s.start_with?("#{directory}/")

    path.to_s
  rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR
    nil
  end
end
