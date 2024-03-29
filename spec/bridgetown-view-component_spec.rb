# frozen_string_literal: true

require "spec_helper"

describe(Bridgetown::ViewComponent) do
  let(:overrides) { {} }
  let(:config) do
    Bridgetown.configuration(Bridgetown::Utils.deep_merge_hashes({
      "full_rebuild" => true,
      "root_dir"     => root_dir,
      "source"       => source_dir,
      "destination"  => dest_dir,
    }, overrides)).tap do |conf|
      conf.run_initializers! context: :static
    end
  end
  let(:metadata_overrides) { {} }
  let(:metadata_defaults) do
    {
      "name" => "My Awesome Site",
      "author" => {
        "name" => "Ada Lovejoy",
      }
    }
  end
  let(:site) { Bridgetown::Site.new(config) }
  let(:contents) { File.read(dest_dir("index.html")) }
  before(:each) do
    metadata = metadata_defaults.merge(metadata_overrides).to_yaml.sub("---\n", "")
    File.write(source_dir("_data/site_metadata.yml"), metadata)
    site.process
    FileUtils.rm(source_dir("_data/site_metadata.yml"))
  end

  it "outputs the rendered ViewComponent" do
    expect(contents).to match "Greetings Bridgetown"
    expect(contents).to match "<hr>\n"
    expect(contents).to match "<strong>Post 1</strong> <span>-&gt;</span>"
    expect(contents).to match "<strong>Post 2</strong> <span>-&gt;</span>"
  end
end
