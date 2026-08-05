class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization

  def index
    @labels = policy_scope(Current.account.labels)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params)
  rescue StandardError => e
    Rails.logger.error("[LabelsController#create] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))

    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @label.update!(permitted_params)
  rescue StandardError => e
    Rails.logger.error("[LabelsController#update] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))

    render json: { error: e.message }, status: :unprocessable_entity
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
end
