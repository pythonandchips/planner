# frozen_string_literal: true

RSpec.describe Planner::TableOfContent, :aggregate_failures do
  it 'puts the file in the folder' do
    expect(described_class.path('docs/plans/x')).to eq('docs/plans/x/TABLE-OF-CONTENT.md')
  end

  it 'renders the format without update rules' do
    section = described_class.section('docs/plans/x', update: false)

    expect(section).to include('# Table of contents — x', '| Status | Completed |', 'Not completed',
                               'grouped by number', '`NNN - <summary>`', '- [PLAN-<NNN>.md](PLAN-<NNN>.md) (<status>)',
                               '- [<folder>/](<folder>/)', 'by the plain line `Other`')
    expect(section).not_to include('If `docs/plans/x/TABLE-OF-CONTENT.md` exists', '<%')
  end

  it 'renders the update rules before the format' do
    section = described_class.section('docs/plans/x', update: true)

    expect(section).to include('If `docs/plans/x/TABLE-OF-CONTENT.md` exists', 'do not create it',
                               '# Table of contents — x', 'adding the group if it is missing',
                               'rewrite the summary line of every group')
  end
end
