class TelegramMessageSender
  include Sidekiq::Worker
  sidekiq_options queue: :telegram,
                  rate: {
                      name: 'telegram_rate_limit',
                      limit: 25,
                      period: 1
                  }

  TELEGRAM_MESSAGE_SENDER_LOG = Logger.new(Rails.root.join('log/intouch', 'telegram-message-sender.log'))

  def perform(telegram_user_id, message)
    token = Setting.plugin_redmine_intouch['telegram_bot_token']
    bot = Telegrammer::Bot.new(token)

    begin
      bot.send_message(chat_id: telegram_user_id, text: message, disable_web_page_preview: true, parse_mode: 'Markdown')
    rescue Telegrammer::Errors::BadRequestError => e
      telegram_user = TelegramUser.find telegram_user_id
      if e.message.include? 'Bot was kicked'
        telegram_user.deactivate
        TELEGRAM_MESSAGE_SENDER_LOG.info "Bot was kicked from chat. Deactivate #{telegram_user.inspect}"
      else
        TELEGRAM_MESSAGE_SENDER_LOG.error "#{e.class}: #{e.message}"
        TELEGRAM_MESSAGE_SENDER_LOG.debug "#{telegram_user.inspect}"
      end
    end
  end

end
