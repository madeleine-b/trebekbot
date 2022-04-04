class Game < ApplicationRecord
  belongs_to :team
  has_many :answers, -> { order 'created_at DESC' }, dependent: :destroy

  validates :category, presence: true
  validates :question, presence: true
  validates :answer, presence: true
  validates :value, presence: true
  validates :air_date, presence: true

  after_commit :enqueue_message_update, if: :saved_change_to_is_closed?

  def self.closeable
    where(is_closed: false).where('created_at < ?', 10.minutes.ago)
  end

  def post_to_slack
    blocks = to_blocks
    text = "The category is #{category}, for $#{value}: “#{question}”"
    response = team.post_message(channel_id: channel, text: text, blocks: blocks)
    self.ts = response.dig(:message, :ts)
    self.save!
  end

  def update_message
    return if team.has_invalid_token?
    blocks = to_blocks
    text = "The category is #{category}, for $#{value}: “#{question}”"
    response = team.update_message(ts: ts, channel_id: channel, text: text, blocks: blocks)
  end

  def close!
    self.is_closed = true
    save!
  end

  def has_correct_answer?
    answers.any?(&:is_correct?)
  end

  def has_answer_by_user?(user)
    answers.where(user: user).present?
  end

  private

  def enqueue_message_update
    UpdateGameMessageWorker.perform_async(id)
  end

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

    if is_closed?
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
          text: "The answer is “#{answer}”"
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
            text: "Your answer, in the form of a question…"
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
        type: "divider"
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
      type: "divider"
    }
    blocks
  end
end
