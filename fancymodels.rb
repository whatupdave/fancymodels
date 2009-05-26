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

      def cant_be_blank
        add_constraint(:cant_be_blank){ |v| !v.blank? }
      end

      def add_constraint(name, &blk)
        @constraints << [name, blk]
      end

      def yaml(value)
        "#{@name}: #{value.to_s}"
      end
      
      def errors(val)
        errors = []
        @constraints.each do |name,constraint|
          errors << name unless constraint.call(val)
        end
        errors unless errors.empty? 
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
      create_index_table
    end
    
    def create_index_table
      @store.db.create_table @name do
        primary_key :uid, :text, :auto_increment => false
        column :id, :text, :unqiue => true, :index => true
      end
      @index_table = @store.db[@name]
    end
    
    def add_field(name, &definition)
      f = Field.new(self, name)
      f.instance_eval(&definition) if definition
      @klass.send :define_method, name do
        instance_variable_get("@#{name}") || (load && instance_variable_get("@#{name}"))
      end
      @klass.send :attr_writer, name
      
      @fields << f
    end
    
    def validate(document)
      doc_errors = []
      @fields.each do |f|
        field_errors = f.errors(document.get_attr(f.name))
        doc_errors << [f.name, field_errors] if field_errors
      end
      document.errors = doc_errors
      doc_errors.empty?
    end
    
    def load(document)
      return if document.new?
      data = @store.documents_table.first(:uid => document.uid)[:data]
      loaded_fields = case @format
        when 'yaml' : YAML.load(data)
        end 
      loaded_fields.each do |name,val|
        document.set_attr(name,val) unless document.instance_variable_get("@#{name}")
      end
    end
    
    def dump(document)
      case @format
      when 'yaml'
        @fields.map do |f|
          val = document.get_attr(f.name)
          f.yaml(val) unless val.blank?
        end.compact.join("\n")
      end
    end
    
    def find(id)
      @klass.new(id) if @index_table.first(:id => id)
    end
    
    def uid(id)
      "/#{@name}/#{id}.#{@format}"
    end
    
    def exists?(document)
      @store.documents_table.first(:uid => document.uid)
    end
    
    def create(document)
      @store.documents_table.insert(:uid => document.uid, :data => document.dump)
      @index_table.insert({:uid => document.uid}.merge(indexed_fields(document)))
    end
    
    def update(document)
      @store.documents_table.first(:uid => document.uid).update(:data => document.dump)
      @index_table.first(:uid => document.uid).update(indexed_fields(document))
    end
    
    def save(document)
      if document.new?
        create(document)
      else
        update(document)
      end
    end
    
    def indexed_fields(document)
      { :id => document.id }
    end
    
  end
  
  class Document
    
    metaclass.send :attr_accessor, :schema
    
    attr_accessor :errors
    
    attr_reader :id
    
    def initialize(id=nil)
      @id = id || FancyModels.rand_id
    end
    
    def set(hsh = {})
      hsh.each { |name, val| self.set_attr(name,val) }
    end
    
    def valid?
      schema.validate(self)
    end
    
    def exists?
      schema.exists?(self)
    end
    
    def new?
      !exists?
    end
    
    def save
      schema.save(self)
      self
    end
    
    # private
    
    def load(force = false)
      unless @loaded || force
        schema.load(self)
        @loaded = true
      end
    end
    
    def uid
      schema.uid(id)
    end
    
    def get_attr(name)
      self.send(name)
    end
    
    def set_attr(name,val)
      self.send("#{name}=", val)
    end
    
    def dump
      schema.dump(self)
    end
    
    def schema
      self.class.schema
    end
    
    def inspect
      "#<#{schema.name} document>" # todo: dump yaml if yaml format
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
      @db.create_table :documents do
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
      @schemas << s
      metaclass.send(:define_method, schema_name){s}
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