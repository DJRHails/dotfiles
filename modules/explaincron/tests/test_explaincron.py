import pytest
from ..explaincron import convert_aws_cron_to_crontab_guru_link, get_crontab_guru_description

@pytest.mark.parametrize(
    ("cron", "link"),
    [
        ("0 0 1 * *", "https://crontab.guru/#0_0_1_*_*"),
        ("3/5 * * * *", "https://crontab.guru/#3/5_*_*_*_*"),
        ("cron(30 * * * ? *)", "https://crontab.guru/#30_*_*_*_*"),
        ("cron(0 9-17 * * 1-5)", "https://crontab.guru/#0_9-17_*_*_1-5"),
        ("0 */2 * * *", "https://crontab.guru/#0_*/2_*_*_*")
    ]
)
def test_convert_aws_cron_to_crontab_guru_link(cron, link):
    assert convert_aws_cron_to_crontab_guru_link(cron) == link

@pytest.mark.parametrize(
    ("cron", "english_explanation"),
    [
        ("0 0 1 * *", "At 00:00 on day-of-month 1."),
        ("3/5 * * * *", "Every 5th minute, starting 3 minutes past the hour."),
        ("0 0 * * *", "At 00:00."),
        ("* * * * *", "Every minute."),
        ("*/5 * * * *", "Every 5th minute."),
        ("0 */2 * * *", "At minute 0 past every 2nd hour."), # "At the start of every 2nd hour, i.e. every 2 hours."),
        ("0 9-17 * * 1-5", "At minute 0 past every hour from 9 through 17 on every day-of-week from Monday through Friday."),
    ]
)
def test_explaincron(cron, english_explanation):
    link = convert_aws_cron_to_crontab_guru_link(cron)
    description, next = get_crontab_guru_description(link) 
    assert description == english_explanation