<img src="http://www.mailanes.com/logo.svg" width="92px" height="92px"/>

[![EO principles respected here](http://www.elegantobjects.org/badge.svg)](http://www.elegantobjects.org)
[![Managed by Zerocracy](https://www.0crat.com/badge/CAZPZR9FS.svg)](https://www.0crat.com/p/CAZPZR9FS)
[![DevOps By Rultor.com](http://www.rultor.com/b/yegor256/mailanes)](http://www.rultor.com/p/yegor256/mailanes)
[![We recommend RubyMine](http://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![Build Status](https://travis-ci.org/yegor256/mailanes.svg)](https://travis-ci.org/yegor256/mailanes)
[![PDD status](http://www.0pdd.com/svg?name=yegor256/mailanes)](http://www.0pdd.com/p?name=yegor256/mailanes)
[![Test Coverage](https://img.shields.io/codecov/c/github/yegor256/mailanes.svg)](https://codecov.io/github/yegor256/mailanes?branch=master)
[![Maintainability](https://api.codeclimate.com/v1/badges/451556110dacf73cc6f6/maintainability)](https://codeclimate.com/github/yegor256/mailanes/maintainability)

It's an e-mail sending web app.

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
# List of GitHub account who also have access to this list
# and can add recipients to it, via /add?list=ID URL.
friends:
  - yegor256
# If this is set to TRUE an email right after being added
# to this list will be de-activated in all other lists
exclusive: true
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
# SMTP parameters of the email sending server
smtp:
  host: email-smtp.us-east-1.amazonaws.com
  port: 587
  user: AKIAI1TIS4FF6UGJT3CQ
  password: ArPxO8gf56y02G8cKM80IpvMQve8Pss+L4+inJZ3UG3t
```

### Campaign

```yaml
# The title of the campaign
title: Monthlty
# Stop the campaign at this date (it will be deactivated automatically)
until: 03-09-2018
# Maximum amount of emails to be sent per day
speed: 100
notify:
  # Notify in Telegram chat. You can get this number
  # just by starting a chat with https://t.me/mailanes_bot
  telegram: 136544085
```

### Letter

```
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
# not send out any letters after it sends this one.
relax: "20:0:0"
# The ID of the letter to quote while sending this one
quote: 12
```

Here is how your Liquid template may look like:

```liquid
{% if first %}
{{first}},
{% else %}
Hi,
{% endif %}

How are you?

—<br/>
Yegor Bugayenko<br/>
To remove your email ({{email}}) from the list, [click here]({{unsubscribe}}).
```

### Recipient

Not implemented yet...
