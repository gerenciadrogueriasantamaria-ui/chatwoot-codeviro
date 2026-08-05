class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  rescue_from StandardError, with: :render_labels_error

  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization

  def index
    @labels = policy_scope(Current.account.labels)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params)
  end

  def update
    @label.update!(permitted_params)
  end

  def destroy
    label_title = @label.title
    account_id = Current.account.id
    label_deleted_at = Time.current

    @label.destroy!
    Labels::RemoveAssociationsJob.perform_later(
      label_title: label_title,
      account_id: account_id,
      label_deleted_at: label_deleted_at
    )
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  def permitted_params
    source_params = params[:label].present? ? params.require(:label) : params

    source_params.permit(:title, :description, :color, :show_on_sidebar)
  end

  def render_labels_error(error)
    Rails.logger.error("[LabelsController] #{error.class}: #{error.message}")
    Rails.logger.error(error.backtrace.first(20).join("\n")) if error.backtrace.present?

    render json: { error: "#{error.class}: #{error.message}" }, status: :unprocessable_entity
  end
end
