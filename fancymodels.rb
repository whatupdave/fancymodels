require 'rubygems'
require 'sequel'
require 'active_support/core_ext/object/metaclass'

module FancyModels
  
  class Schema
    
    class Field

      attr_reader :name

      def initialize(schema, name)
        @schema, @name = schema, name
        @constraints = []
      end

      def not_blank
        add_constraint(:not_blank){ |v| !v.blank? }
      end

      def add_constraint(name, &blk)
        @constraints << [name, blk]
      end

      def yaml(value)
        "#{@name}: #{value.to_s}"
      end

    end
    
    class Definition
      # supports a dsl
      
      def initialize(schema)
        @schema = schema
      end
      
      def method_missing(field_name, &definition)
        @schema.add_field(field_name, &definition)
      end
      
    end
    
    attr_reader :name, :format
    
    def initialize(store,name)
      @store = store
      @name = name
      @fields = []
      @format = 'yaml'
      @klass = Class.new Document
      @klass.schema = self
    end
    
    def build(hsh = {})
      document = @klass.new
      document.set(hsh) unless hsh.empty?
      document
    end
    alias_method :new, :build
    
    def define(&blk)
      Definition.new(self).instance_eval(&blk)
    end
    
    def add_field(name, &definition)
      f = Field.new(self, name)
      f.instance_eval(&definition) if definition
      @klass.send :attr_accessor, name
      @fields << f
    end
    
    def dump(document)
      case @format
      when "yaml"
        @fields.map do |f|
          val = document.get_attr(f.name)
          f.yaml(val) unless val.blank?
        end.compact.join("\n")
      end
    end
    
    def save(document)
      if row = @store.documents_table.first(:uid => document.uid)
        row.update(:data => document.dump)
      else
        @store.documents_table.insert(:uid => document.uid, :data => document.dump)
      end
    end
    
  end
  
  class Document
    
    class << self
      attr_accessor :schema
    end
    
    def id
      @id ||= FancyModels.rand_id
    end
    
    def uid
      "/#{schema.name}/#{id}.#{schema.format}"
    end
    
    def get_attr(name)
      self.send(name)
    end
    
    def set_attr(name,val)
      self.send("#{name}=", val)
    end
    
    def set(hsh = {})
      hsh.each { |name, val| self.set_attr(name,val) }
    end
    
    def inspect
      "#<#{self.class.schema.name} document>" # todo: dump yaml if yaml format
    end
    
    def schema
      self.class.schema
    end
    
    def dump
      schema.dump(self)
    end
    
    def save
      schema.save(self)
    end
    
  end
  
  class Store
    
    # stores stuff, like a filesystem, except fancier
    
    attr_reader :db
    
    def initialize(db)
      @db = db
      @schemas = []
    end
    
    def create_documents_table
      @db.create_table! :documents do
        primary_key :uid, :text, :auto_increment => false
        # should be byta (or something in postgres) and binary or blob in sqlite
        column :data, :text
      end
    end
    
    def documents_table
      @db[:documents]
    end
    
    def define(schema_name, &definition)
      s = Schema.new(self,schema_name)
      s.define(&definition)
      metaclass.send(:define_method, schema_name){s}
      @schemas << s
    end
    
  end
  
  def self.create_store(db)
    store = Store.new(db)
    store.create_documents_table
    store
  end
  
  # no vowels
  ID_CHARS = ('0'..'9').to_a + (('a'..'z').to_a - ['a','e','i','o','u'])

  def self.rand_id(length=12)
    (1..length).map { ID_CHARS.at( rand(ID_CHARS.size) ) }.join('')
  end
  
end