import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from urllib.parse import urlencode

def send_review_email(
    *,
    subject: str,
    to_email: str,
    html_body: str
):
    host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    port = int(os.getenv("SMTP_PORT", "587"))
    user = os.getenv("SMTP_USER")
    password = os.getenv("SMTP_PASS")

    if not user or not password:
        raise RuntimeError("SMTP_USER/SMTP_PASS missing in .env")

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = user
    msg["To"] = to_email

    msg.attach(MIMEText(html_body, "html", "utf-8"))

    with smtplib.SMTP(host, port) as server:
        server.starttls()
        server.login(user, password)
        server.sendmail(user, [to_email], msg.as_string())

def make_links(pc_ip: str, run_id: str, channel: str):
    # n8n webhooks (we will create these)
    base = f"http://{pc_ip}:5678/webhook"
    approve_long = f"{base}/approve?{urlencode({'run_id': run_id, 'channel': channel, 'kind': 'long'})}"
    approve_short = f"{base}/approve?{urlencode({'run_id': run_id, 'channel': channel, 'kind': 'short'})}"
    reject_all = f"{base}/reject?{urlencode({'run_id': run_id, 'channel': channel})}"
    return approve_long, approve_short, reject_all