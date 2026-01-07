# frozen_string_literal: true

module MessagingSystem
  class NullMetrics
    def increment(*); end
    def decrement(*); end
    def gauge(*); end
    def histogram(*); end
    def timing(*); end
  end
end
