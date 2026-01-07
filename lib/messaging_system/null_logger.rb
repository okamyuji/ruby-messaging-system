# frozen_string_literal: true

module MessagingSystem
  class NullLogger
    def debug(*); end
    def info(*); end
    def warn(*); end
    def error(*); end
    def fatal(*); end
    def level = 0
    def level=(_level); end
  end
end
