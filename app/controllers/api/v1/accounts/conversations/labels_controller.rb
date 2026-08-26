class Api::V1::Accounts::Conversations::LabelsController < Api::V1::Accounts::Conversations::BaseController
  include LabelConcern

  def create
    labels = Array(params[:labels]).compact_blank

    @conversation.label_list = labels.first.present? ? [labels.first] : []
    @conversation.save!
  end

  def destroy
    @conversation.label_list = []
    @conversation.save!
  end

  private

  def model
    @model ||= @conversation
  end

  def permitted_params
    params.permit(:conversation_id, labels: [])
  end
end
