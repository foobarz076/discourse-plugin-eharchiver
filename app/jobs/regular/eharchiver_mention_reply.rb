# frozen_string_literal: true

module Jobs
  class EharchiverMentionReply < ::Jobs::Base
    def execute(args)
      post = Post.find_by(id: args[:post_id])
      Eharchiver::MentionTrigger.process(post) if post
    end
  end
end
