require 'rubygems'
require 'sequel'
require 'active_support/core_ext/object/metaclass'
require 'active_support/core_ext/blank'
require 'active_support/ordered_hash'

module FancyModels
  
  require 'schema'
  require 'document'
  
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