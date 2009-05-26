require 'rubygems'
require 'sequel'
require 'active_support/core_ext/object/metaclass'
require 'active_support/core_ext/blank'

module FancyModels
  
  class Schema
    
    # Builds a new document and sets the attributes given. Does not save the document
    def new(hsh = {})
      document = @klass.new
      document.set(hsh) unless hsh.empty?
      document
    end
    
    # Find document with given id
    def find(id)
      @klass.new(id) if @index_table.first(:id => id)
    end
    
    # == private implementation
    
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
    
    def uid(id)
      "/#{@name}/#{id}.#{@format}"
    end
    
    def exists?(document)
      !!@store.documents_table.first(:uid => document.uid)
    end
    
    def create(document)
      @store.documents_table.insert(:uid => document.uid, :data => document.dump)
      @index_table.insert({:uid => document.uid}.merge(indexed_fields(document)))
    end
    
    def update(document)
      @store.documents_table.filter(:uid => document.uid).update(:data => document.dump)
      @index_table.filter(:uid => document.uid).update(indexed_fields(document))
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
    
    attr_reader :id
    
    def initialize(id=nil)
      @id = id || FancyModels.rand_id
    end
    
    # Set a bunch of attributes. 
    # E.g. 
    #     doc.set :name => "Myles", :city => "Sydney"
    # is equvalent to:
    #     doc.name = "Myles" ; doc.city = "Sydney"
    def set(hsh = {})
      hsh.each { |name, val| self.set_attr(name,val) }
    end
    
    # validates the document, validation errors can be retreived by calling #errors
    def valid?
      schema.validate(self)
    end
    
    attr_accessor :errors
    
    # true if document exists in the store
    def exists?
      schema.exists?(self)
    end
    
    # true if document does not exist in the store
    def new?
      !exists?
    end
    
    # save the document to the store, does not validate first, that is up to you, returns document
    def save
      schema.save(self)
      self
    end
    
    # == private implementation
    
    metaclass.send :attr_accessor, :schema
    
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
    
    # define a schema for storing documents
    def define(schema_name, &definition)
      s = Schema.new(self,schema_name)
      s.define(&definition)
      @schemas << s
      metaclass.send(:define_method, schema_name){s}
    end
    
    # == private implementation
    
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
    
  end
  
  # creates a new store and connects it to the given db. You probably want
  # to store the return value of this call in a constant so you can access
  # it from anywhere in you program. E.g.
  #     MyStore = FancyModels.create_store Sequel.sqlite
  def self.create_store(db)
    store = Store.new(db)
    store.create_documents_table
    store
  end

  # == private implementation
  
  # no vowels
  ID_CHARS = ('0'..'9').to_a + (('a'..'z').to_a - ['a','e','i','o','u'])

  def self.rand_id(length=12)
    (1..length).map { ID_CHARS.at( rand(ID_CHARS.size) ) }.join('')
  end
  
end