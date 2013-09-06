@name = 'Progress report wrapper'

@description = %q{
  This plugin wraps the report object while Puppet runs through a transaction,
  sending the progress back over a socket so an external process can track
  the run.  Yes, this is quite evil.
}

require 'socket'
$kafo_socket = UNIXSocket.new(ENV['KAFO_PROGRESS'])

module Kafo
  module Puppet
    class ReportWrapper
      attr_reader :transaction, :report

      def initialize(transaction, report)
        @transaction = transaction
        @report = report
      end

      # Needed to fool Puppet's logging framework
      def self.to_s
        "Puppet::Transaction::Report"
      end

      def add_resource_status(status)
        if transaction.in_main_catalog && report.resource_statuses[status.resource.to_s] && transaction.is_interesting?(status.resource)
          $kafo_socket.puts "RESOURCE #{status.resource}"
        end
        report.add_resource_status(status)
      end

      def method_missing(method, *args)
        report.send(method, *args)
      end
    end
  end
end

# Monkey patch the transaction to put our wrapper around the report object
require 'puppet/transaction'
class Puppet::Transaction
  attr_accessor :in_main_catalog

  def is_interesting? resource
    ![:schedule, :class, :stage, :filebucket].include?(resource.to_s.split('[')[0].downcase.to_sym)
  end

  def resource_count
    catalog.vertices.select { |resource| is_interesting?(resource) }.size
  end

  def evaluate_with_trigger
    if catalog.version
      self.in_main_catalog = true
      $kafo_socket.puts "START #{resource_count}"
    end
    evaluate_without_trigger
    self.in_main_catalog = false if catalog.version
  end
  alias_method :evaluate_without_trigger, :evaluate
  alias_method :evaluate, :evaluate_with_trigger

  def report_with_wrapper
    unless @report_wrapper
      @report_wrapper = Kafo::Puppet::ReportWrapper.new(self, report_without_wrapper)
    end
    @report_wrapper
  end
  alias_method :report_without_wrapper, :report
  alias_method :report, :report_with_wrapper
end
