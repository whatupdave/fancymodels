require 'rubygems'
require 'sequel'
require 'active_support/core_ext/object/metaclass'
require 'active_support/core_ext/blank'

module FancyModels
  
  require 'schema'
  
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
      self
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
      # @schemas << s
      metaclass.send(:define_method, schema_name){s}
      s
    end
    
    # == private implementation
    
    attr_reader :db
    
    def initialize(db)
      @db = db
      # @schemas = []
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