"""Built-in service workers for common integrations.

Each worker is a :class:`~apiary_sdk.ServiceWorker` subclass that bridges an
external service into the Apiary task bus.  Import the ones you need and
instantiate them with your credentials::

    from apiary_sdk.workers import HttpWorker, SlackWorker

    worker = SlackWorker(
        base_url="https://apiary.example.com",
        hive_id="01HXYZ...",
        agent_id="01HABC...",
        secret="s3cr3t",
    )
    worker.run()

Optional dependency groups (install with pip):

- ``apiary-sdk[http]``     — :class:`HttpWorker`
- ``apiary-sdk[github]``   — :class:`GitHubWorker`
- ``apiary-sdk[slack]``    — :class:`SlackWorker`
- ``apiary-sdk[gmail]``    — :class:`GmailWorker`
- ``apiary-sdk[sheets]``   — :class:`SheetsWorker`
- ``apiary-sdk[jira]``     — :class:`JiraWorker`
- ``apiary-sdk[sql]``      — :class:`SqlWorker`
- ``apiary-sdk[workers]``  — all of the above
"""

from apiary_sdk.workers.github import GitHubWorker
from apiary_sdk.workers.gmail import GmailWorker
from apiary_sdk.workers.http import HttpWorker
from apiary_sdk.workers.jira import JiraWorker
from apiary_sdk.workers.sheets import SheetsWorker
from apiary_sdk.workers.slack import SlackWorker
from apiary_sdk.workers.sql import SqlWorker

__all__ = [
    "GitHubWorker",
    "GmailWorker",
    "HttpWorker",
    "JiraWorker",
    "SheetsWorker",
    "SlackWorker",
    "SqlWorker",
]
