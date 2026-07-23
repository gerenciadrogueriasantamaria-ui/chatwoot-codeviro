class DeviseOverrides::SessionsController < DeviseTokenAuth::SessionsController
  # Prevent session parameter from being passed
  # Unpermitted parameter: session
  wrap_parameters format: []
  before_action :process_sso_auth_token, only: [:create]

  def new
    redirect_to login_page_url(error: 'access-denied')
  end

  def create
    return handle_mfa_verification if mfa_verification_request?
    return handle_sso_authentication if sso_authentication_request?

    user = find_user_for_authentication
    return render_agent_access_denied(user) if agent_access_denied?(user)
    return handle_mfa_required(user) if user&.mfa_enabled?
  
    # Only proceed with standard authentication if no MFA is required
    super
  end

  def render_create_success
    register_agent_access_session
    response.set_header('X-Agent-Access-Client-Id', @agent_access_guard.client_id) if @agent_access_guard

    render partial: 'devise/auth', formats: [:json], locals: { resource: @resource }
  end

  def destroy
  revoke_agent_access_session
  super
  end

  private

  def revoke_agent_access_session
  return unless current_user

  account = agent_access_account_for(current_user)
  return unless account

  client_id = request.headers['X-Agent-Access-Client-Id']
  return if client_id.blank?

  account.agent_access_sessions
         .active
         .where(user: current_user, client_id: client_id)
         .find_each(&:revoke!)
  end

  def agent_access_denied?(user)
  return false unless user

  account = agent_access_account_for(user)
  return false unless account

  @agent_access_guard = AgentAccess::SessionGuard.new(
    user: user,
    account: account,
    request: request,
    client_id: request.headers['X-Agent-Access-Client-Id']
  )

  !@agent_access_guard.allowed?
end

def render_agent_access_denied(user)
  reason = @agent_access_guard&.denial_reason || 'access_denied'

  render json: {
    success: false,
    error: agent_access_error_message(reason),
    error_code: reason
  }, status: :unauthorized
end

def register_agent_access_session
  return unless @resource

  account = agent_access_account_for(@resource)
  return unless account

  @agent_access_guard ||= AgentAccess::SessionGuard.new(
    user: @resource,
    account: account,
    request: request,
    client_id: request.headers['X-Agent-Access-Client-Id']
  )

  @agent_access_guard.register!
end

def agent_access_account_for(user)
  return Account.find_by(id: params[:account_id]) if params[:account_id].present?

  user.accounts.first
end

def agent_access_error_message(reason)
  case reason
  when 'outside_schedule'
    'No puedes ingresar fuera de tu horario permitido.'
  when 'max_sessions_reached'
    'Ya alcanzaste el límite de sesiones activas.'
  else
    'No tienes permitido ingresar al CRM.'
  end
end
  
  def render_create_error_not_confirmed
    render_error(
      :unauthorized,
      I18n.t('devise_token_auth.sessions.not_confirmed', email: @resource.email),
      error_code: 'user_not_confirmed'
    )
  end

  def find_user_for_authentication
    return nil unless params[:email].present? && params[:password].present?

    normalized_email = params[:email].strip.downcase
    user = User.from_email(normalized_email)
    return nil unless user&.valid_password?(params[:password])
    return nil unless user.active_for_authentication?

    user
  end

  def mfa_verification_request?
    params[:mfa_token].present?
  end

  def sso_authentication_request?
    params[:sso_auth_token].present? && @resource.present?
  end

  def handle_sso_authentication
    authenticate_resource_with_sso_token
    yield @resource if block_given?
    render_create_success
  end

  def login_page_url(error: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)

    "#{frontend_url}/app/login?error=#{error}"
  end

  def authenticate_resource_with_sso_token
    @token = @resource.create_token
    @resource.save!

    sign_in(:user, @resource, store: false, bypass: false)
    # invalidate the token after the user is signed in
    @resource.invalidate_sso_auth_token(params[:sso_auth_token])
  end

  def process_sso_auth_token
    return if params[:email].blank?

    user = User.from_email(params[:email])
    @resource = user if user&.valid_sso_auth_token?(params[:sso_auth_token])
  end

  def handle_mfa_required(user)
    render json: {
      mfa_required: true,
      mfa_token: Mfa::TokenService.new(user: user).generate_token
    }, status: :partial_content
  end

  def handle_mfa_verification
    user = Mfa::TokenService.new(token: params[:mfa_token]).verify_token
    return render_mfa_error('errors.mfa.invalid_token', :unauthorized) unless user

    authenticated = Mfa::AuthenticationService.new(
      user: user,
      otp_code: params[:otp_code],
      backup_code: params[:backup_code]
    ).authenticate

    return render_mfa_error('errors.mfa.invalid_code') unless authenticated

    sign_in_mfa_user(user)
  end

  def sign_in_mfa_user(user)
    @resource = user
    @token = @resource.create_token
    @resource.save!

    sign_in(:user, @resource, store: false, bypass: false)
    render_create_success
  end

  def render_mfa_error(message_key, status = :bad_request)
    render json: { error: I18n.t(message_key) }, status: status
  end
end

DeviseOverrides::SessionsController.prepend_mod_with('DeviseOverrides::SessionsController')
