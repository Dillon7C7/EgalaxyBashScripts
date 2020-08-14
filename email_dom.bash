#!/bin/bash

show_num="$1"

subject="Subject: Show ${show_num}"
from="From: FROM_ADDRESS"
to="To: TO_ADDRESS"
cc="Cc: CC_ADDRESSES"
date="Date: $(date -R)"

IFS= read -r -d '\0' message <<- EMAIL_DOC
	${from}
	${to}
	${cc}
	${subject}
	${date}
	MIME-Version: 1.0
	Content-Type: text/plain; charset=utf-8; format=flowed
	Content-Transfer-Encoding: 7bit
	Content-Language: en-US

	Hi Domenic,
	
	A new show is uploaded. Please find it here:
	REMOTE_HOST
	
	Full res video and mp3
	
	Thank you,
	
	Dillon
	\0
EMAIL_DOC

printf "%s\\n" "$message" | msmtp --read-recipients
