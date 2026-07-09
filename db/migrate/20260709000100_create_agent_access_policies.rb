class CreateAgentAccessPolicies < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_access_policies do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: true
      t.integer :max_sessions, null: false, default: 1
      t.jsonb :schedule, null: false, default: {}

      t.timestamps
    end

    add_index :agent_access_policies,
              [:account_id, :user_id],
              unique: true,
              name: 'index_agent_access_policies_on_account_and_user'
  end
end
