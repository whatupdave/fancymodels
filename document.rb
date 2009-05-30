module FancyModels
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
end