require_relative '../entity_serializer'

module UnitOfWork
  # CAVEAT: this is not distribution-friendly. object_id should use 'nodename' as well
  class ObjectHistory
    def initialize
      @object_ids = {}
    end
    def <<(obj)
      # TODO the 'deep clone' part should be moved to a Serialization Mixin
      oid = obj.object_id.to_s.to_sym
      @object_ids[oid] = Array(@object_ids[oid]) << EntitySerializer.clone(obj)
    end
    def [](oid)
      @object_ids[oid.to_s.to_sym]
    end
  end
end