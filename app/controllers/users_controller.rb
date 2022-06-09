class UsersController < ApplicationController
  authorize_resource

  def index
    @users = User.active.not_students
    @user_groups = @users.group_by { |u| u.role }
  end

  def blocked
    @users = User.blocked.not_students
    @user_groups = @users.group_by { |u| u.role }
    render 'index'
  end

  def activity
    @user = User.not_students.find(params[:id])

    #@audits = @user.audits # | @user. | @user.theses.collect { |t| t.associated_audits }.flatten
    #@audits = @user.audits #+ @user.associated_audits #Audited::Adapters::ActiveRecord::Audit.where(user_id: @user.id)
    @audits = Audited::Audit.where(user_id: @user.id).limit(500)
    @audits = @audits.sort { |a, b| a.created_at <=> b.created_at }

    @audits_grouped = @audits.reverse.group_by { |a| a.created_at.at_beginning_of_day }
  end

  def show
    @user = User.not_students.find(params[:id])
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.created_by = current_user
    @user.blocked ||= false
    @user.audit_comment = "Added a new user"

    if @user.save
      redirect_to users_path, :notice => "Successfully created user #{@user.username}."
    else
      render :action => 'new'
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    @user.audit_comment = "Updated a user"
    if @user.update_attributes(user_params)
      redirect_to users_path, :notice  => "Successfully updated user #{@user.username}."
    else
      render :action => 'edit'
    end
  end

  def block
    @user = User.find(params[:id])
    @user.audit_comment = "Blocked this user"
    @user.block unless @user.id == current_user.id
    redirect_to users_path, notice: "Blocked #{@user.name}"
  end

  def unblock
    @user = User.find(params[:id])
    @user.audit_comment = "Unblocked this user"
    @user.unblock
    redirect_to blocked_users_path, notice: "Unblocked #{@user.name}"
  end

  def destroy

    if params[:id].to_i == current_user.id
      redirect_to users_url, :alert => "You are not allowed to disable yourself"
    else
      @user = User.find(params[:id])
      @user.audit_comment = "Blocked the user"
      @user.blocked = true
      @user.save
      redirect_to users_url, :notice => "Successfully disabled this user."
    end
  end

  private
  def user_params
    params.require(:user).permit(:username, :name, :email, :role)
  end
end
