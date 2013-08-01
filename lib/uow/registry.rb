require 'singleton'

module TransactionRegistry

  # TODO maybe the registry should store nodename/class/id/transaction/state - this would allow easier distribution
  class Registry
    class RegistrySearchResult
      attr_reader :transaction, :state
      def initialize(tr, st)
        @transaction = tr
        @state = st
      end
    end

    include Singleton
    def initialize
      @@registry = {}
    end
    def [](tr)
      @@registry[tr]
    end
    def <<(tr)
      @@registry[tr.uuid.to_sym] = tr
    end
    def delete(tr)
      @@registry.delete(tr.uuid.to_sym)
    end
    def find_transactions(obj)
      @@registry.reduce([]) do |m,(uuid,tr)|
        res = tr.fetch_object(obj)
        if !res.nil? && obj === res.object
          m<< RegistrySearchResult.new(tr, res.state)
        else
          m
        end
      end
    end
    # TODO create/read file for each Transaction
    def marshall_dump
    end
    def marshall_load
    end
  end

  module FinderService
    module ClassMethods
      def self.extended(base_class)
        base_class.instance_eval {
          def fetch_from_transaction(uuid, obj_id)
            tr = Registry.instance[uuid.to_sym]
            (tr.nil?) ? nil : tr.fetch_object_by_id(self, obj_id)
          end
        }
      end
    end
    module InstanceMethods
      def transactions
        Registry.instance.find_transactions(self)
      end
    end
  end

end
