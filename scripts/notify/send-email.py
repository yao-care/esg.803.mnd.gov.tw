#!/usr/bin/env python3
"""
寄送 HTML email（附件）
用法: send-email.py --from "Name <email>" --to "a@b.com,c@d.com" --subject "..." --body email.html --attachments "dir/*.html"
環境變數: SMTP_USERNAME, SMTP_PASSWORD
"""
import smtplib, os, sys, glob, argparse
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

parser = argparse.ArgumentParser()
parser.add_argument('--from-addr', required=True)
parser.add_argument('--to', required=True)
parser.add_argument('--subject', required=True)
parser.add_argument('--body', required=True, help='Path to HTML file')
parser.add_argument('--attachments', default='', help='Glob pattern for attachments')
args = parser.parse_args()

username = os.environ.get('SMTP_USERNAME', '')
password = os.environ.get('SMTP_PASSWORD', '')

if not username or not password:
    print('ERROR: SMTP_USERNAME and SMTP_PASSWORD env vars required')
    sys.exit(1)

msg = MIMEMultipart()
msg['From'] = args.from_addr
msg['To'] = args.to
msg['Subject'] = args.subject

with open(args.body, 'r', encoding='utf-8') as f:
    msg.attach(MIMEText(f.read(), 'html', 'utf-8'))

if args.attachments:
    for filepath in glob.glob(args.attachments):
        if 'email-body' in os.path.basename(filepath):
            continue
        with open(filepath, 'rb') as f:
            part = MIMEBase('text', 'html')
            part.set_payload(f.read())
            encoders.encode_base64(part)
            part.add_header('Content-Disposition', 'attachment', filename=os.path.basename(filepath))
            msg.attach(part)

with smtplib.SMTP('smtp.gmail.com', 587) as s:
    s.starttls()
    s.login(username, password)
    s.send_message(msg)

print(f'Email sent to {args.to}')
