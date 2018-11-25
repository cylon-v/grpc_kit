# frozen_string_literal: true

module GrpcKit
  module GRPC
    module DefaultLogger
      # @return [Logger]
      def self.logger
        LOGGER
      end

      LOGGER = Logger.new(STDOUT)
    end

    unless methods.include?(:logger)
      extend DefaultLogger
    end
  end
end
