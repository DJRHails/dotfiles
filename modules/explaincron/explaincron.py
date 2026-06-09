#!/usr/bin/env python3

# Example: echo "0 0 1 * *" | explaincron
# Example: explaincron "0 0 1 * *"
# Example: echo "cron(30 * * * ? *)" | explaincron

from datetime import datetime
import re
import sys
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

CRON_WRAPPER_REGEX = re.compile(
    r"""(?ix)         # case-insensitive, verbose
    ^cron\(           # AWS-style "cron(" wrapper at the start
    (?P<body>.*)      # the cron fields inside the wrapper
    \)$               # closing parenthesis at the end
    """
)

def convert_aws_cron_to_crontab_guru_link(cron_expression):
    # Strip an AWS-style cron(...) wrapper, then split on whitespace so lists
    # (1,15) and names (MON-FRI) pass through verbatim — crontab.guru handles them.
    expression = cron_expression.strip()
    wrapper = CRON_WRAPPER_REGEX.match(expression)
    if wrapper:
        expression = wrapper.group("body")
    fields = expression.split()
    if len(fields) not in (5, 6):
        raise ValueError(
            f"Expected 5 or 6 cron fields, got {len(fields)} in {cron_expression!r}"
        )

    # Drop the AWS year field and convert ? (no specific value) to *
    fields = ['*' if field == '?' else field for field in fields[:5]]

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

def unique(items):
    return list(dict.fromkeys(items))

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