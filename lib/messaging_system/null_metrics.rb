# frozen_string_literal: true

module MessagingSystem
  class NullMetrics
    def increment(*) = nil
    def decrement(*) = nil
    def gauge(*) = nil
    def histogram(*) = nil
    def timing(*) = nil
  end
end
