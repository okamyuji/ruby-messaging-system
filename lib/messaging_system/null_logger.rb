# frozen_string_literal: true

module MessagingSystem
  class NullLogger
    def debug(*) = nil
    def info(*) = nil
    def warn(*) = nil
    def error(*) = nil
    def fatal(*) = nil
    def level = 0
    def level=(_level); end
  end
end
