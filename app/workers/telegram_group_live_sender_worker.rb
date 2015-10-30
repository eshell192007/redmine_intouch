class TelegramGroupLiveSenderWorker
  include Sidekiq::Worker

  def perform(issue_id)
    Intouch.set_locale

    issue = Issue.find issue_id
    telegram_groups_settings = issue.project.active_telegram_settings.try(:[], 'groups')

    return unless telegram_groups_settings.present?

    group_ids = telegram_groups_settings.select do |k, v|
      v.try(:[], issue.status_id.to_s).try(:include?, issue.priority_id.to_s)
    end.keys

    only_unassigned_group_ids = telegram_groups_settings.select { |k, v| v.try(:[], 'only_unassigned').present? }.keys

    group_ids -= only_unassigned_group_ids unless issue.total_unassigned?

    group_for_send_ids = if issue.alarm? or Intouch.work_time?

                           group_ids

                         else
                           anytime_group_ids = telegram_groups_settings.select { |k, v| v.try(:[], 'anytime').present? }.keys

                           (group_ids & anytime_group_ids)
                         end

    return unless group_for_send_ids.present?

    message = issue.telegram_live_message

    token = Setting.plugin_redmine_intouch['telegram_bot_token']
    bot = Telegrammer::Bot.new(token)

    TelegramGroupChat.where(id: group_for_send_ids).uniq.each do |group|
      next unless group.tid.present?
      bot.send_message(chat_id: -group.tid, text: message, disable_web_page_preview: true, parse_mode: 'Markdown')
    end
  end
end
