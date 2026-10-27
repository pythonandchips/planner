# frozen_string_literal: true

require 'open3'

RSpec.describe 'exe/planner', :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  let(:repo) { File.expand_path('../..', __dir__) }

  def planner(*)
    Open3.capture3('ruby', "-I#{repo}/lib", "#{repo}/exe/planner", *)
  end

  it 'prints usage and exits 1 with no args' do
    _out, err, status = planner

    expect(status.exitstatus).to eq(1)
    expect(err).to eq(Planner::CLI::USAGE)
  end

  it 'creates a plan folder with new' do
    out, _err, status = planner('new', 'Hello World')

    expect(status.exitstatus).to eq(0)
    expect(out).to match(%r{\Adocs/plans/\d{12}-hello-world\n\z})
    expect(File.directory?(out.chomp)).to be(true)
  end

  it 'reports a missing iteration file' do
    _out, err, status = planner('plan', 'ITERATION-001.md')

    expect(status.exitstatus).to eq(1)
    expect(err).to eq("[planner] ITERATION-001.md does not exist\n")
  end
end
