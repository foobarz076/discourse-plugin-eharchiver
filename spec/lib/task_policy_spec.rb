# frozen_string_literal: true

RSpec.describe Eharchiver::TaskPolicy do
  before do
    SiteSetting.eharchiver_request_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.eharchiver_original_download_groups = Group::AUTO_GROUPS[:admins]
    SiteSetting.eharchiver_paid_download_groups = Group::AUTO_GROUPS[:admins]
    SiteSetting.eharchiver_elevated_spending_groups = Group::AUTO_GROUPS[:admins]
    SiteSetting.eharchiver_standard_max_gp_per_download = 100
    SiteSetting.eharchiver_elevated_max_gp_per_download = 500
    SiteSetting.eharchiver_min_remaining_gp = 100_000
  end

  it "keeps ordinary users at a zero GP authorization" do
    result =
      described_class.authorize!(
        user: Fabricate(:user),
        topic: Fabricate(:topic),
        quality: "resample",
      )

    expect(result.max_cost_gp).to eq(0)
    expect(result.min_remaining_gp).to eq(100_000)
  end

  it "falls back to resample when the default is original but the user lacks permission" do
    SiteSetting.eharchiver_default_archive_quality = "original"

    result =
      described_class.authorize!(user: Fabricate(:user), topic: Fabricate(:topic), quality: nil)

    expect(result.quality).to eq("resample")
  end

  it "separately enforces original quality and elevated spending groups" do
    admin = Fabricate(:admin)
    result = described_class.authorize!(user: admin, topic: Fabricate(:topic), quality: "original")
    expect(result.max_cost_gp).to eq(500)

    expect do
      described_class.authorize!(
        user: Fabricate(:user),
        topic: Fabricate(:topic),
        quality: "original",
      )
    end.to raise_error(Eharchiver::PolicyDenied)
  end
end
