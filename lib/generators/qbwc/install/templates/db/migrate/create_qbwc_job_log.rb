# frozen_string_literal: true
# lib/generators/qbwc/install/templates/db/migrate/create_qbwc_jobs.rb
class CreateQbwcJobLog < ActiveRecord::Migration[5.0]
  def change
    create_table :qbwc_job_logs, :force => true do |t|
      t.string :job_name
      t.string :company, :limit => 1000
      t.string :ticket, :limit => 1000
      t.text :error
      t.datetime :processed_at
      t.timestamps :null => false
    end
  end
end


