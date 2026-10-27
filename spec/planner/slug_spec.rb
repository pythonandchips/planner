# frozen_string_literal: true

RSpec.describe Planner::Slug do
  {
    'Hello World' => 'hello-world',
    '  --Foo__Bar!! ' => 'foo-bar',
    '!!!' => '',
    'Café' => 'caf'
  }.each do |input, expected|
    it "turns #{input.inspect} into #{expected.inspect}" do
      expect(described_class.call(input)).to eq(expected)
    end
  end
end
