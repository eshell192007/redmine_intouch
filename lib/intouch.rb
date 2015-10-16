module Intouch

  def self.send_notifications(issues, state)
    issues.group_by(&:project_id).each do |project_id, project_issues|

      project = Project.find_by id: project_id
      next unless project.present?

      reminder_settings = project.active_reminder_settings
      telegram_settings = project.active_telegram_settings

      if project.module_enabled?(:intouch) and project.active? and reminder_settings.present?

        project_issues.each do |issue|

          if issue.alarm? or Intouch.work_time?

            priority = issue.priority_id.to_s
            active = reminder_settings[priority].try(:[], 'active')
            interval = if %w(unassigned assigned_to_group).include? state
                         3
                       else
                         reminder_settings[priority].try(:[], 'interval')
                       end
            last_notification = issue.last_notification.try(:[], state)

            if active and
                interval.present? and
                issue.updated_on < interval.to_i.hours.ago and
                (last_notification.nil? or last_notification < interval.to_i.hours.ago)

              IntouchSender.send_telegram_message(issue.id, state)
              IntouchSender.send_email_message(issue.id, state) unless %w(overdue without_due_date).include? state

              group_ids = telegram_settings.try(:[], state).try(:[], 'groups')
              IntouchSender.send_telegram_group_message(issue_id, group_ids) if group_ids.present?

              issue.last_notification = {} unless issue.last_notification.present?
              issue.last_notification[state] = Time.now
            end
          end
        end
      end
    end
  end

  def self.send_bulk_email_notifications(issues, state)
    if Intouch.work_day? or true
      user_issues_ids = {}
      issues.group_by(&:project_id).each do |project_id, project_issues|

        project = Project.find_by id: project_id
        next unless project.present?

        if project.module_enabled?(:intouch) and project.active?

          project_issues.each do |issue|

            user_ids = issue.recipient_ids('email', state)
            user_ids && user_ids.each do |user_id|
              user_issues_ids[user_id] = [] if user_issues_ids[user_id].nil?
              user_issues_ids[user_id] << issue.id
            end

          end
        end
      end

      user_issues_ids.each do |user_id, issue_ids|
        IntouchMailer.overdue_issues_email(user_id, issue_ids).deliver
      end
    end
  end


  def self.work_day?
    settings = Setting.plugin_redmine_intouch
    work_days = settings.keys.select { |key| key.include?('work_days') }.map { |key| key.split('_').last.to_i }
    work_days.include? Date.today.wday
  end

  def self.work_time?
    from = Time.parse Setting.plugin_redmine_intouch['work_day_from']
    to = Time.parse Setting.plugin_redmine_intouch['work_day_to']
    work_day? and from <= Time.now and Time.now <= to
  end

end