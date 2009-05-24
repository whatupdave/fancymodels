require 'rubygems'
require 'sequel'

module FancyModels
  
  class Field
    
    attr_reader :name
    
    def initialize(type, name)
      @type, @name = type, name
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
  
  class Document
    
    class << self
      attr_accessor :type
    end
    
    def id
      @id ||= FancyModels.rand_id
    end
    
    def uid
      "/#{record_type.name}/#{id}.#{record_type.format}"
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
      "#<#{self.class.type.name} record>" # todo: dump yaml if yaml format
    end
    
    def record_type
      self.class.type
    end
    
    def dump
      record_type.dump(self)
    end
    
    def save
      record_type.save(self)
    end
    
  end
  
  class Type
    
    # kind of like tables, name always plural
    
    class Definition
      # supports a dsl
      
      def initialize(type)
        @type = type
      end
      
      def method_missing(field_name, &definition)
        @type.add_field(field_name, &definition)
      end
      
    end
    
    attr_reader :name, :format
    
    def initialize(store,name)
      @store = store
      @name = name
      @fields = []
      @format = 'yaml'
      @klass = Class.new Document
      @klass.type = self
    end
    
    def build(hsh = {})
      # klass.instance_eval
      record = @klass.new
      record.set(hsh) unless hsh.empty?
      record
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
    
    def dump(record)
      case @format
      when "yaml"
        @fields.map do |f|
          val = record.get_attr(f.name)
          f.yaml(val) unless val.blank?
        end.compact.join("\n")
      end
    end
    
    def save(record)
      if row = @store.documents_table.first(:uid => record.uid)
        row.update(:data => record.dump)
      else
        @store.documents_table.insert(:uid => record.uid, :data => record.dump)
      end
    end
    
  end
  
  class Store
    
    # stores stuff, like a filesystem, except fancier
    
    attr_reader :db
    
    def initialize(db)
      @db = db
      @types = []
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
    
    def define(type_name, &definition)
      t = Type.new(self,type_name)
      t.define(&definition)
      # todo: define type accessor methods here, then remove method missing
      @types << t
    end
    
    # probably don't need this
    def method_missing(msg, *args)
      @types.find { |t| msg == t.name } || super
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

require 'spec'

def clip(str)
  str.gsub( str.match(/\n\s+/)[0], "\n" ).strip
end

describe "simple store with one model" do
  
  before do
    @s = FancyModels.create_store Sequel.sqlite
    @s.define :restaurants do 
      name { not_blank }
      slug
      phone
    end
  end
  
  example "new store dbs have a documents table" do
    @s.db[:documents].count.should == 0
  end
  
  example "record instances can be created with new" do
    r = @s.restaurants.new
    r.class.superclass.should == FancyModels::Document
  end
  
  example "by default, ids are random 12 char strings" do
    r = @s.restaurants.new
    r.id.size.should == 12
  end
  
  example "default type 'format' is yaml" do
    @s.restaurants.format == 'yaml'
  end
  
  example "uids look like path portions of urls" do
    r = @s.restaurants.new
    r.instance_eval {@id = 'tdfjtscvm3v1'}
    r.uid.should == "/restaurants/tdfjtscvm3v1.yaml"
  end
  
  example "records with a type that has a yaml format dump to deterministic yaml" do
    r = @s.restaurants.new
    r.set(
      :name => 'Ambalas',
      :slug => 'ambalas',
      :phone => '0299999999'
    )
    r.dump.should == clip(%{
      name: Ambalas
      slug: ambalas
      phone: 0299999999
    })
  end
  
  example "saving record should write the output of #dump to the record's row" do
    r = @s.restaurants.new :name => "Test"
    r.save
    @s.documents_table.first(:uid => r.uid)[:data].should == r.dump
  end

end