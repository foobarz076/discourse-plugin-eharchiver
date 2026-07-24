# frozen_string_literal: true

module Eharchiver
  class TaskPolicy
    Result = Data.define(:quality, :max_cost_gp, :min_remaining_gp)

    def self.authorize!(user:, topic:, quality:)
      if !user.in_any_groups?(SiteSetting.eharchiver_request_allowed_groups_map)
        raise PolicyDenied, "User is not allowed to request archive tasks."
      end

      allowed_categories = SiteSetting.eharchiver_allowed_categories.to_s.split("|").map(&:to_i)
      if allowed_categories.present? && allowed_categories.exclude?(topic.category_id)
        raise PolicyDenied, "This category does not allow archive tasks."
      end

      requested_quality = quality.presence
      normalized_quality = requested_quality || SiteSetting.eharchiver_default_archive_quality
      if !%w[resample original].include?(normalized_quality)
        raise Discourse::InvalidParameters.new(:quality)
      end
      if normalized_quality == "original" &&
           !user.in_any_groups?(SiteSetting.eharchiver_original_download_groups_map)
        if requested_quality.nil?
          normalized_quality = "resample"
        else
          raise PolicyDenied, "User is not allowed to request original archives."
        end
      end

      max_cost_gp = 0
      if user.in_any_groups?(SiteSetting.eharchiver_paid_download_groups_map)
        max_cost_gp =
          if user.in_any_groups?(SiteSetting.eharchiver_elevated_spending_groups_map)
            SiteSetting.eharchiver_elevated_max_gp_per_download
          else
            SiteSetting.eharchiver_standard_max_gp_per_download
          end
      end

      Result.new(
        quality: normalized_quality,
        max_cost_gp: max_cost_gp,
        min_remaining_gp: SiteSetting.eharchiver_min_remaining_gp,
      )
    end
  end
end
