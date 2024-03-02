#!/usr/bin/env python3

# Example: echo "0 0 1 * *" | explaincron
# Example: explaincron "0 0 1 * *"
# Example: echo "cron(30 * * * ? *)" | explaincron

from datetime import datetime
import re
import sys
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

CRON_PART_REGEX = r"""
(?:             # Start of non-capturing group for the primary part
    \d+         # Matches one or more digits. This is used for specific time points, like "5" in minute field for the 5th minute.
    |           # OR operator
    [*?]        # Matches either a star or a question mark. Star (*) is used for 'every' time unit, question mark (?) is used for 'no specific value'.
)               # End of primary part
(?:             # Start of non-capturing group for the secondary part
    [/\-]       # Matches either a slash or a dash. Slash (/) is used for step values, like "*/15" in minute field for every 15 minutes. Dash (-) is used for ranges, like "5-10" in hour field for between 5 and 10.
    \d+         # Matches one or more digits. This is the value used with the slash or dash in the secondary part.
)?              # End of secondary part. The group is optional, as not all cron parts have a secondary part.
"""

def convert_aws_cron_to_crontab_guru_link(cron_expression):
    # Extract the minute, hour, day of month, month, and day of week fields
    fields = re.findall(CRON_PART_REGEX, cron_expression, re.X)[:5]
    
    # Convert ? to * for the day of week field
    for i, field in enumerate(fields):
        if field == '?':
            fields[i] = '*'
    
    # Build the crontab.guru link
    link = f"https://crontab.guru/#{'_'.join(fields)}"
    
    return link

def get_crontab_guru_description(url) -> tuple[str, list[datetime]]:
    # Configure Chrome options
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--disable-gpu')
    
    # Start Chrome driver
    driver = webdriver.Chrome(options=options)
    
    print(f"Fetching '{url}'")
    # Fetch the crontab.guru page
    driver.get(url)
    
    # Wait for the page to load
    wait = WebDriverWait(driver, 10)
    
    next_button = wait.until(EC.element_to_be_clickable((By.CLASS_NAME, 'clickable')))
    next_button.click()
    
    # Wait for the page to update
    wait.until(EC.presence_of_element_located((By.CLASS_NAME, 'human-readable')))
    
    # Extract the human-readable description from the page
    description = driver.execute_script("""
        return document.querySelector('.human-readable').textContent;
    """)
    next_time = driver.execute_script("""
        return document.querySelector('.next-date').textContent;
    """)
    
    # Quit Chrome driver
    driver.quit()
    
    # Remove smart quotes
    description = re.sub(r"[\u2018\u2019\u00b4]", "", description)
    description = re.sub(r"[\u201c\u201d\u2033]", "", description)
    description = description.strip()
    
    # minute from <d> through 59 -> minute, starting <d> minutes past the hour
    description = re.sub(r' from (\d+) through 59', r', starting \1 minutes past the hour', description)
    
    # At every -> Every
    description = description.replace("At every", "Every")
    
    # Extract the next times
    next_times = re.findall(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}', next_time)
    next_times = [datetime.strptime(next_time, "%Y-%m-%d %H:%M:%S") for next_time in next_times]

    return description, next_times

def unique(l):
    return list(dict.fromkeys(l))

if __name__ == '__main__':
    # Read the input cron expression from either stdin or argument
    if sys.stdin.isatty():
        expression = sys.argv[1]
    else:
        expression = sys.stdin.read().strip()
    
    for cron in unique(expression.split('\n')):
        print(f"== {cron} ==")
        # Convert the AWS cron expression to a crontab.guru link
        link = convert_aws_cron_to_crontab_guru_link(cron)
        description, next = get_crontab_guru_description(link)

        # Print the description and open the link in the browser
        print(description)
        for next_time in next:
            print(f"> {next_time:%Y-%m-%d %H:%M:%S}")