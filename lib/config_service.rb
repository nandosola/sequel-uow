# -*- encoding : utf-8 -*-
require 'sequel'

# Sequel config
Sequel.extension :inflector
Sequel.datetime_class = DateTime

module Dilithium
  module DatabaseUtils
  end
  module EntityMapper
    module Sequel
    end
  end
  module InheritanceMapper
    module Sequel
    end
  end
  module Repository
    module Sequel
    end
  end
  class SharedVersion
  end

  module PersistenceService
    module Sequel
      def self.db=(db)
        SchemaUtils::Sequel.const_set(:DB, db)
        DefaultMapper::Sequel.const_set(:DB, db)
        EntityMapper::Sequel.const_set(:DB, db)
        ValueMapper::Sequel.const_set(:DB, db)
        InheritanceMapper::Sequel.const_set(:DB, db)
        Repository::Sequel.const_set(:DB, db)
        SharedVersion.const_set(:DB, db)
        IntegerSequence.const_set(:DB, db)
      end
    end
  end
end
