module FancyModels
  class Schema

    # Builds a new document and sets the attributes given. Does not save the document
    def new(hsh = {})
      document = new_document
      document.set(hsh) unless hsh.empty?
      document
    end

    # Find document with given id
    def find(id)
      @klass.new(id) if @index_table.first(:id => id)
    end

    # Define a sub-schema, where this schema has one (or none) instances of said sub-schema
    def have_one(name, &definition)
      subschema = define_subschema(name,&definition)
      add_have_one_association(subschema)
      # metaclass.send(:define_method, schema_name){schema}
      subschema
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

    attr_reader :name, :format, :associations
    attr_accessor :parent

    def initialize(store,name)
      @store = store
      @name = name
      @fields = []
      @associations = ActiveSupport::OrderedHash.new # too tricky? array of pairs clearer?
      @format = 'yaml'
      @klass = Class.new Document
      @klass.schema = self
    end

    def define(&blk)
      Definition.new(self).instance_eval(&blk)
      create_index_table
    end
    
    def define_subschema(name, &definition)
      # schema = self.class.new(@store,"#{@name}_#{name}")
      schema = self.class.new(@store,name)
      schema.define(&definition)
      schema
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
      
    # documents associated with have_one have the same id (but not uid) as their parent
    def add_have_one_association(schema)
      schema.parent = self
      @associations[schema] = :have_one
      @klass.send :define_method, "#{schema.name}=" do |attribs|
        instance_variable_set("@#{schema.name}", schema.new_document(self.id).set(attribs))
      end
      @klass.send :attr_reader, schema.name
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
      "#{path(id)}.#{@format}"
    end
    
    def parent?
      @parent
    end
    
    def parent_association
      @parent.associations[self]
    end
    
    def path(id)
      if parent? && parent_association == :have_one
        "#{@parent.path(id)}/#{name}"
      else
        "/#{@name}/#{id}"
      end
    end

    def exists?(document)
      !!@store.documents_table.first(:uid => document.uid)
    end
    
    def new_document(id=nil)
      @klass.new(id)
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
end