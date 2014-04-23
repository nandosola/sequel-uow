# -*- encoding : utf-8 -*-

module Dilithium

  module BaseEntityPayload
    def content
      raise NotImplementedError, 'Please define the content() method'
    end
  end

  class RestoredPayload
    include BaseEntityPayload
    def initialize(restored_entity)
      raise ArgumentError, "Entity #{restored_entity.class} is not a BaseEntity!" unless restored_entity.is_a?(Dilithium::DomainObject)
      @domain_object = restored_entity
    end
    def content
      EntitySerializer.to_nested_hash(@domain_object)
    end
  end

  class BaseEntityMassUpdater
    SECURE_KEYS = [:_version]
    
    class ChildPayload
      TYPE_KEY = :_type
      include BaseEntityPayload

      def initialize(child_h)
        @child_h = child_h
        @type = child_h.delete(TYPE_KEY)
      end
      def content
        @child_h
      end
      def child_type(parent_class)
        raise ArgumentError "Argument must be a Class. Got #{parent_class}" unless parent_class.is_a?(Class)
        if @type.nil?
          nil
        else
          module_path = parent_class.to_s.split('::')
          child_literal = @type.to_s.singularize.camelize
          module_path.pop
          module_path.push(child_literal)
          module_path.reduce(Object){ |m,c| m.const_get(c) }
        end
      end
    end

    def initialize(entity, payload)
      raise ArgumentError, "Entity #{entity.class} is not a BaseEntity!" unless entity.is_a?(Dilithium::BaseEntity)
      raise ArgumentError, "Entity #{entity.class} is not a BaseEntityPayload!" unless payload.class.include?(BaseEntityPayload)
      payload_h = payload.content
      raise ArgumentError, "Payload content is nil" if payload_h.nil?
      @entity = entity

      unless payload_h.empty?
        sanitize_keys!(payload_h)
        check_input_h(payload_h)
      end
      @sanitized_payload_h = payload_h
    end

    def update!
      unless @sanitized_payload_h.empty?
        @entity.send(:_detach_children)
        @entity.send(:_detach_multi_references)
        update_attributes
        update_immutable_references
        update_children
        update_multi_references
      end
    end

    private

    def sanitize_keys!(in_h)
      SECURE_KEYS.each{|k| in_h.delete(k) }

      (@entity.class.identifier_names.each do |id|
        old_id = @entity.instance_variable_get(:"@#{id}")
        if old_id != in_h[id]
          raise ArgumentError, "Entity id cannot be changed once defined." +
            "Offending key: #{id} new value: '#{in_h[id]}' was: '#{old_id}'"
        end
      end) unless in_h.empty?
    end

    def check_input_h(in_h)
      attributes = @entity.class.attribute_descriptors
      attr_keys = attributes.keys
      in_h.each do |k,v|
        base_name = k.to_s.chomp("_id").to_sym
        if attributes.include?(k)
          attribute_name = k
        elsif [BasicAttributes::ImmutableReference, BasicAttributes::ImmutableMultiReference].include?(attributes[base_name].class)
          attribute_name = base_name
          v = {:id => v}
        end

        raise ArgumentError, "Attribute #{k} is not allowed in #{@entity.class}" unless attr_keys.include?(attribute_name)
        attributes[base_name].check_constraints(v)
      end
    end

    def update_attributes
      @entity.class.attribute_descriptors.each do |k,v|
        @entity.instance_variable_set("@#{k}".to_sym, v.default) unless v.is_a? BasicAttributes::ParentReference
      end

      @entity.class.attributes.select { |attr| attr.is_attribute? }.each do |attr|
        attr_name = attr.name
        value = if @sanitized_payload_h.include?(attr_name)
                  attr_value = @sanitized_payload_h[attr_name]

                  if attr.is_a?(BasicAttributes::ValueReference) && attr_value.is_a?(Hash)
                    keys = attr.type.identifier_names.map{ |id| attr_value[id]}
                    Repository.for(attr.type).fetch_by_id(*keys)
                  else
                    attr_value
                  end
                else
                  attr.default
                end

        @entity.send("#{attr_name}=".to_sym,value)

        @sanitized_payload_h.delete(attr_name)
      end
    end

    def update_children
      @entity.class.each_attribute(BasicAttributes::ChildReference) do |attr|
        child_name = attr.name
        children_h = if @sanitized_payload_h[child_name].nil?
                       attr.default
                     else
                       @sanitized_payload_h[child_name]
                     end

        children_h.each do |child_h|
          child_payload = ChildPayload.new(child_h)
          @entity.send("make_#{child_name.to_s.singularize}", child_payload.child_type(@entity.class)) do |child|
            # FIXME (SECURITY ISSUE): only assign id from children with an existing id
            child.id = child_h[:id]
            BaseEntityMassUpdater.new(child, child_payload).update!
          end
        end
      end
    end

    def update_multi_references
      @entity.class.each_attribute(BasicAttributes::MultiReference) do |attr|
        __attr_name = attr.name
        value = if @sanitized_payload_h[__attr_name].nil?
                  attr.default
                else
                  @sanitized_payload_h[__attr_name]
                end

        value.each { |ref| @entity.send("add_#{__attr_name.to_s.singularize}".to_sym, ref) }
      end
    end

    def update_immutable_references
      @entity.class.each_attribute(BasicAttributes::ImmutableReference) do |attr|
        __attr_name = attr.name
        in_value = @sanitized_payload_h[__attr_name]
        value = case in_value
                  #FIXME We should NEVER get a Hash at this level
                  when Hash
                    Association::ImmutableEntityReference.new(in_value[:id], attr.type)
                  when Association::ImmutableEntityReference, BaseEntity, NilClass
                    in_value
                  else
                    raise IllegalArgumentException, "Invalid reference #{__attr_name}. Should be Hash or ImmutableEntityReference, is #{in_value.class}"
                end

        @entity.send("#{__attr_name}=".to_sym,value)
      end

      @entity.class.each_attribute(BasicAttributes::ImmutableMultiReference) do |attr|
        __attr_name = attr.name
        in_array = @sanitized_payload_h[__attr_name]

        unless in_array.nil?
          in_array.each do |in_value|
            value = case in_value
                      #FIXME We should NEVER get a Hash at this level
                      when Hash
                        Association::ImmutableEntityReference.new(in_value[:id], attr.inner_type)
                      when Association::ImmutableEntityReference, NilClass
                        in_value
                      when BaseEntity
                        in_value.immutable
                      else
                        raise IllegalArgumentException, "Invalid reference #{__attr_name}. Should be Hash or ImmutableEntityReference, is #{in_value.class}"
                    end

            send("add_#{__attr_name.to_s.singularize}".to_sym, value)
          end
        end

        @sanitized_payload_h.delete(__attr_name)
      end
    end

  end
end