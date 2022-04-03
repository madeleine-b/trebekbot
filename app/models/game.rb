class Game < ApplicationRecord
  belongs_to :team
  has_many :answers, -> { order 'created_at DESC' }, dependent: :destroy

  validates :category, presence: true
  validates :question, presence: true
  validates :answer, presence: true
  validates :value, presence: true
  validates :air_date, presence: true

  def post_to_slack
    blocks = to_blocks
    text = "The category is #{category}, for $#{value}: “#{question}”"
    response = team.post_message(channel_id: channel, text: text, blocks: blocks)
    self.ts = response.dig(:message, :ts)
    self.save!
  end

  def has_correct_answer?
    answers.any?(&:is_correct?)
  end

  def update_message
    return if team.has_invalid_token?
    blocks = to_blocks
    text = "The category is #{category}, for $#{value}: “#{question}”"
    slack = Slack.new
    response = slack.update_message(access_token: team.access_token, ts: ts, channel_id: channel, text: text, blocks: blocks)
    raise response[:error] unless response[:ok]
    logger.info "Updated message #{ts} in channel #{channel}"
    response
  end

  private

  def to_blocks
    blocks = []
    blocks << {
			type: "context",
			elements: [
				{
					type: "mrkdwn",
					text: "*#{category.titleize}* | $#{value}"
				}
			]
		}

    if has_correct_answer? || is_closed?
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*#{question}*"
        }
      }
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "Answer: #{answer}"
        }
      }
    else
      blocks << {
        type: "input",
        dispatch_action: true,
        element: {
          type: "plain_text_input",
          action_id: "answer",
          placeholder: {
            type: "plain_text",
            text: "Your answer, in the form of a question"
          },
          dispatch_action_config: {
            trigger_actions_on: [
              "on_enter_pressed"
            ]
          }
        },
        label: {
          type: "plain_text",
          text: question
        }
      }
    end

    if answers.present?
      blocks << {
        "type": "divider"
      }
      answers.each do |a|
        blocks << {
          type: "context",
          elements: [
            {
              type: "plain_text",
              text: a.emoji,
              emoji: true
            },
            {
              type: "image",
              image_url: a.user.avatar,
              alt_text: a.user.name
            },
            {
              type: "plain_text",
              text: a.answer,
              emoji: true
            }
          ]
        }
      end
    end
    blocks << {
      "type": "divider"
    }
    blocks << {
			type: "context",
			elements: [
				{
					type: "plain_text",
					text: "Originally aired on #{air_date.strftime('%A, %B %-d, %Y')}"
				}
			]
		}
    blocks
  end
end
