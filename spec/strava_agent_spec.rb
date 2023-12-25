require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::StravaAgent do
  before(:each) do
    @valid_options = Agents::StravaAgent.new.default_options
    @checker = Agents::StravaAgent.new(:name => "StravaAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
