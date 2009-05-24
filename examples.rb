require 'fancymodels'
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
  
  example "document instances can be created with new" do
    r = @s.restaurants.new
    r.class.superclass.should == FancyModels::Document
  end
  
  example "by default, ids are random 12 char strings" do
    r = @s.restaurants.new
    r.id.size.should == 12
  end
  
  example "default schema 'format' is yaml" do
    @s.restaurants.format == 'yaml'
  end
  
  example "uids look like path portions of urls" do
    r = @s.restaurants.new
    r.instance_eval {@id = 'tdfjtscvm3v1'}
    r.uid.should == "/restaurants/tdfjtscvm3v1.yaml"
  end
  
  example "documents with a schema that has a yaml format dump to deterministic yaml" do
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
  
  example "saving document should write the output of #dump to the document's row" do
    r = @s.restaurants.new :name => "Test"
    r.save
    @s.documents_table.first(:uid => r.uid)[:data].should == r.dump
  end

end