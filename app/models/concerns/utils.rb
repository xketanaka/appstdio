class Utils
  extend FormatUtils

  def self.error_log(e, logger)
    logger.error e.class
    logger.error e.message
    logger.error e.backtrace.slice(0, 15).join("\n")
    if Rails.env.development?
      puts e.class
      puts e.message
      puts e.backtrace.slice(0, 15).join("\n")
    end
  end
end
