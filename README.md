# Mass E-Mailing Web Service

[![EO principles respected here](https://www.elegantobjects.org/badge.svg)](https://www.elegantobjects.org)
[![DevOps By Rultor.com](https://www.rultor.com/b/yegor256/mailanes)](https://www.rultor.com/p/yegor256/mailanes)
[![We recommend RubyMine](https://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![rake](https://github.com/yegor256/mailanes/actions/workflows/rake.yml/badge.svg)](https://github.com/yegor256/mailanes/actions/workflows/rake.yml)
[![PDD status](https://www.0pdd.com/svg?name=yegor256/mailanes)](https://www.0pdd.com/p?name=yegor256/mailanes)
[![Test Coverage](https://img.shields.io/codecov/c/github/yegor256/mailanes.svg)](https://codecov.io/github/yegor256/mailanes?branch=master)
[![Maintainability](https://api.codeclimate.com/v1/badges/451556110dacf73cc6f6/maintainability)](https://codeclimate.com/github/yegor256/mailanes/maintainability)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/yegor256/mailanes/blob/master/LICENSE.txt)
[![Availability at SixNines](https://www.sixnines.io/b/8f0c)](https://www.sixnines.io/h/8f0c)
[![Hits-of-Code](https://hitsofcode.com/github/yegor256/mailanes)](https://hitsofcode.com/view/github/yegor256/mailanes)

It's an e-mail sending web app.

Read this blog post, it explains how it works:
[_Mailanes.com Helps Manage Newsletters and Mailing Lists_][blog].

## How to Configure?

There are few entities you can configure via simple [YAML](http://yaml.org/)
settings, including lists, lanes, campaigns, letters, and recipients.

### List

```yaml
title: My subscribers
notify:
  # Notify this email every time a new subscriber
  # is added to the list through the /subscribe URL
  email: yegor256@gmail.com
  # Notify in Telegram chat. You can get this number
  # just by starting a chat with https://t.me/mailanes_bot
  telegram: 136544085
  # You may ignore some notifications
  ignore:
    - subscribe
    - unsubscribe
    - add
    - comment
    - download
    - upload
    - bounce
# List of GitHub account who also have access to this list
# and can add recipients to it, via /add?list=ID URL.
friends:
  - yegor256
# If this is set to TRUE an email right after being added
# to this list will be de-activated in all other lists
exclusive: true
# If this is TRUE, all new recipients that get into the list via the
# /subscribe link, will be marked as non-yet-confirmed. They will have
# to click the link, which is available in your Markdown template
# as {{confirm}} (similar to the {{unsubscribe}} you have there).
# The default is FALSE.
confirmation_required: true
```

### Lane

```yaml
title: Monthly newsletters
# The FROM field of all letters to be sent from this
# Lane. This can be overwritten by each individual Letter.
from: Yegor Bugayenko <yegor256@gmail.com>
# The CC of the email to be sent
cc:
  - Yegor Bugayenko <yegor256@gmail.com>
# The BCC of the email to be sent
bcc:
  - Yegor Bugayenko <yegor256@gmail.com>
# The TO field of all emails to be sent, which
# you don't need to specify usually, since this
# address is taken from the recipient details, but sometimes
# you may need this.
to: Yegor Bugayenko <yegor256@gmail.com>
# The email to collect all bounces (the default is `reply@mailanes.com`)
bounces: reply@mailanes.com
# SMTP parameters of the email sending server
smtp:
  host: email-smtp.us-east-1.amazonaws.com
  port: 587
  user: AKIAI1TIS4FF6UGJT3CQ
  password: ArPxO8gf56y02G8cKM80IpvMQve8Pss+L4+inJZ3UG3t
# Here you can specify the Telegram transport details, if
# some of your letters are going to be delivered via Telegram.
telegram:
  chat_id: 7389473289
```

### Campaign

```yaml
# The title of the campaign
title: Monthly
# Stop the campaign at this date (it will be deactivated automatically)
until: 03-09-2018
# Maximum amount of emails to be sent per day
speed: 100
notify:
  # Notify in Telegram chat. You can get this number
  # just by starting a chat with https://t.me/mailanes_bot
  telegram: 136544085
# Send fake emails to this address, in order to
# lower the bounce-back stats of the SMTP providers (recommended)
decoy:
  # How many fake emails per each real email
  amount: 0.1
  # Destination address ('*' will be replaced by a random 0-9 number)
  address: my-fake***@example.com
```

### Letter

```yaml
# The title of the letter
title: Aug 2018
# The subject of all emails to be sent
subject: There are some great news, guys!
# The FROM field of all emails to be sent
from: Yegor Bugayenko <yegor256@gmail.com>
# The CC of the email to be sent
cc:
  - Yegor Bugayenko <yegor256@gmail.com>
# The BCC of the email to be sent
bcc:
  - Yegor Bugayenko <yegor256@gmail.com>
# The TO field of all emails to be sent, which
# you don't need to specify usually, since this
# address is taken from the recipient details, but sometimes
# you may need this.
to: Yegor Bugayenko <yegor256@gmail.com>
# When this Letter has to be deactivated
until: 03-09-2018
# For how many days/hours/minutes the campaign should
# not send out any letters after it sends this one. There
# are three possible formats:
#  hh:mm:ss    - exactly how much time it should relax
#  dd-mm-yyyy  - when exactly it should relax
#  sss         - in how many seconds
relax: "20:0:0"
# The ID of the letter to quote while sending this one
quote: 12
# This can be either SMTP or Telegram. If it's SMTP, you have
# to specify the SMTP section in the Lane. If it's Telegram,
# you have to specify telegram chat ID in the Lane.
transport: SMTP
# Maximum amount of emails to be sent per day
speed: 100
# Turn OFF email opening tracking feature (ON by default)
tracking: off
```

Here is how your Liquid template may look like:

```liquid
{% if first %}
{{first}},
{% else %}
Hi,
{% endif %}

How are you? Thanks for joining my list. Please
[click here]({{confirm}}) to confirm that you are serious
and want to stay.

—<br/>
Yegor Bugayenko<br/>
To remove your email ({{email}}) from the list, [click here]({{unsubscribe}}).
```

### Recipient

Not implemented yet...

## API

You can retrieve the data from the system via the API. First, you have
to get the authorization code from the
[API page](https://www.mailaines.com/api).
Then, add it to each HTTP request you make, as `auth` URI parameter.
For example,
to see the total count of all active subscribers of your list:

`/api/lists/123/active_count.json?auth=74fa8672...`

All URIs:

* `/api/lists/:id/active_count.json`: total active subscribers in the list
* `/api/lists/:id/per_day.json`: new subscribers per day
(last 10 days stat, change with `days`)
* `/api/campaigns/:id/deliveries_count.json`: deliveries per day
(last day, change with `days`)
* more coming...

## How to contribute

Read these [guidelines].
Make sure your build is green before you contribute
your pull request. You will need to have [Ruby] 2.3+,
Java 8+, Maven 3.2+, PostgreSQL 10+, and
[Bundler](https://bundler.io/) installed. Then:

```bash
bundle update
bundle exec rake
```

If it's clean and you don't see any error messages, submit your pull request.

To run a single unit test you should first do this:

```bash
bundle exec rake pgsql liquibase run
```

And then, in another terminal (for example):

```bash
bundle exec ruby test/test_campaign.rb -n test_iterates_lists
```

Should work.

[blog]: https://www.yegor256.com/2018/10/30/mailanes.html
[guidelines]: https://www.yegor256.com/2014/04/15/github-guidelines.html
[Ruby]: https://www.ruby-lang.org/en/
