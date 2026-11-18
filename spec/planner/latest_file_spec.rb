# frozen_string_literal: true

RSpec.describe Planner::LatestFile, :aggregate_failures do
  let(:any) { /\A(?:PLAN|ITERATION|FINDINGS|REVIEW)-\d+(?:-[a-z]+)?\.md\z/ }
  let(:plan) { /\APLAN-\d+\.md\z/ }

  def resolve(accepted = any) = described_class.resolve('x', accepted, 'PLAN-<N>.md')

  def write(*names)
    FileUtils.mkdir_p('x')
    names.each { |name| File.write("x/#{name}", 'x') }
  end

  it 'returns a file path unchanged' do
    File.write('PLAN-001.md', 'x')

    expect(described_class.resolve('PLAN-001.md', plan, 'PLAN-<N>.md')).to eq('PLAN-001.md')
  end

  it 'returns a missing path unchanged' do
    expect(described_class.resolve('nope', plan, 'PLAN-<N>.md')).to eq('nope')
  end

  it 'picks the highest number, compared as integers' do
    write('PLAN-009.md', 'PLAN-010.md', 'PLAN-002.md')

    expect(resolve(plan)).to eq('x/PLAN-010.md')
  end

  it 'ignores files of other kinds' do
    write('PLAN-002.md', 'ITERATION-003.md')

    expect(resolve(plan)).to eq('x/PLAN-002.md')
  end

  it 'picks the last letter' do
    write('FINDINGS-002.md', 'FINDINGS-002-a.md', 'FINDINGS-002-b.md')

    expect(resolve).to eq('x/FINDINGS-002-b.md')
  end

  it 'orders longer letters after shorter ones' do
    write('FINDINGS-002-z.md', 'FINDINGS-002-aa.md')

    expect(resolve).to eq('x/FINDINGS-002-aa.md')
  end

  it 'raises Error naming both files when two kinds share the highest number' do
    write('REVIEW-003.md', 'PLAN-003.md', 'PLAN-002.md')

    expect { resolve }.to raise_error(
      Planner::Error, 'x has more than one latest file: PLAN-003.md, REVIEW-003.md; give the file instead'
    )
  end

  it 'raises Error when no file matches' do
    write('ITERATION-001.md')

    expect { resolve(plan) }.to raise_error(Planner::Error, 'x has no PLAN-<N>.md file')
  end

  it 'ignores a subfolder' do
    write('PLAN-001.md')
    FileUtils.mkdir_p('x/PLAN-002.md')

    expect(resolve(plan)).to eq('x/PLAN-001.md')
  end
end
