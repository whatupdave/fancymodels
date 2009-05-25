require 'fancymodels'
require 'spec'

describe "not blank validation" do
  
  before do
    @s = FancyModels.create_store Sequel.sqlite
    @s.define :people do 
      name { cant_be_blank }
    end
  end
  
  example "field not blank" do
    r = @s.people.new(:name => 'Myles')
    r.should be_valid
  end
  
  example "field blank" do
    r = @s.people.new
    r.should_not be_valid
  end

end