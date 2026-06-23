class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show
  mark_current_user_online!
  end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
  account_user = @user.account_users.find_by(account_id: profile_params[:account_id])
  account_user.update(active_at: Time.now.utc)
  mark_current_user_online!(account_user.account_id)
  head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  private

  def mark_current_user_online!(account_id = nil)
  account_user = if account_id.present?
                   @user.account_users.find_by(account_id: account_id)
                 else
                   @user.active_account_user
                 end

  return if account_user.blank?

  account_user.update!(availability: :online, auto_offline: true)
  OnlineStatusTracker.update_presence(account_user.account_id, 'User', @user.id)
  OnlineStatusTracker.set_status(account_user.account_id, @user.id, 'online')
  end

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
