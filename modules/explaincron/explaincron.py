#!/usr/bin/env python3

# Example: echo "0 0 1 * *" | explaincron
# Example: explaincron "0 0 1 * *"
# Example: echo "cron(30 * * * ? *)" | explaincron

import re
import sys
import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

def convert_aws_cron_to_crontab_guru_link(cron_expression):
    # Extract the minute, hour, day of month, month, and day of week fields
    fields = re.findall(r'\d+|[*?]', cron_expression)[:5]
    
    # Convert ? to * for the day of week field
    for i, field in enumerate(fields):
        if field == '?':
            fields[i] = '*'
    
    # Build the crontab.guru link
    link = f"https://crontab.guru/#{'_'.join(fields)}"
    
    return link

def get_crontab_guru_description(url):
    # Configure Chrome options
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--disable-gpu')
    
    # Start Chrome driver
    driver = webdriver.Chrome(options=options)
    
    print(f"Fetching {url}...")
    # Fetch the crontab.guru page
    driver.get(url)
    
    # Wait for the page to load
    time.sleep(1)
    
    # Extract the human-readable description from the page
    description = driver.execute_script("""
        return document.querySelector('.human-readable').textContent.trim();
    """)
    next_time = driver.execute_script("""
        return document.querySelector('.next-date').textContent.trim();
    """)
    
    # Quit Chrome driver
    driver.quit()
    
    return description, next_time

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
        print(next)