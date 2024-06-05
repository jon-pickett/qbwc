# lib/qbwc/active_record/job_log.rb
module QBWC
  module ActiveRecord
    class JobLog < ::ActiveRecord::Base
      self.table_name = 'qbwc_job_logs'

      validates :job_name, presence: true
      validates :company, presence: true
      validates :ticket, presence: true
      validates :processed_at, presence: true

      def self.last_successful_run(job_name)
        where(job_name: job_name).where.not(processed_at: nil).where(error: nil).order(processed_at: :desc).first
      end
    end
  end
end