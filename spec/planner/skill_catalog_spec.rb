# frozen_string_literal: true

RSpec.describe Planner::SkillCatalog, :aggregate_failures do
  def write_skill(slug, content, *extra)
    FileUtils.mkdir_p("skills/#{slug}")
    File.write("skills/#{slug}/SKILL.md", content)
    extra.each do |file|
      FileUtils.mkdir_p(File.dirname("skills/#{slug}/#{file}"))
      File.write("skills/#{slug}/#{file}", 'x')
    end
  end

  def description_of(content)
    write_skill('s', content)
    described_class.all(Pathname('skills')).first.description
  end

  it 'returns no skills for a missing dir' do
    expect(described_class.all(Pathname('skills'))).to eq([])
  end

  context 'with several folders' do
    subject(:skills) { described_class.all(Pathname('skills')) }

    before do
      write_skill('b', "---\nname: b\ndescription: Bee\n---\nBody\n")
      write_skill('a', "---\nname: a\ndescription: Ay\n---\nBody\n", 'scripts/x.sh')
      FileUtils.mkdir_p('skills/c')
      File.write('skills/notes.md', 'notes')
    end

    it 'finds the folders with a SKILL.md, sorted by slug' do
      expect(skills.map(&:slug)).to eq(%w[a b])
      expect(skills.map(&:description)).to eq(%w[Ay Bee])
      expect(skills.map(&:path)).to eq([Pathname('skills/a'), Pathname('skills/b')])
    end
  end

  it 'gives a blank description when it cannot read one' do
    expect(description_of("# No frontmatter\n")).to eq('')
    expect(description_of("---\ndescription: [\n---\nBody\n")).to eq('')
    expect(description_of("---\ndescription: Dated\ncreated: 2026-01-01\n---\nBody\n")).to eq('')
    expect(description_of("---\nname: s\n---\nBody\n")).to eq('')
  end

  it 'every shipped skill names itself and has a description' do
    described_class.all(described_class::DIR).each do |skill|
      expect(described_class.frontmatter(skill.path / 'SKILL.md')['name']).to eq(skill.slug)
      expect(skill.description.strip).not_to be_empty
    end
  end
end
