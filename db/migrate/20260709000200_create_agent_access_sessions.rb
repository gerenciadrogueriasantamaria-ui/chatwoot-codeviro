class CreateAgentAccessSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_access_sessions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_seen_at
      t.datetime :expires_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :agent_access_sessions,
              [:account_id, :user_id, :client_id],
              unique: true,
              name: 'index_agent_access_sessions_on_account_user_client'

    add_index :agent_access_sessions, :revoked_at
    add_index :agent_access_sessions, :expires_at
  end
end
