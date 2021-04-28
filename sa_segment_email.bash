#!/bin/bash

paste -d ' ' \
<(awk '{print $0 ")"}' numbers) \
<(date -f air-dates +'%b %d -') \
<(awk \
'NR==FNR {
	haves[$0]=$0; next
	} 
	{
		if (FNR in haves) {
			print $0, "- Already have"
		}
		else {
			print $0
		}
	}' \
have-segments segment-ids) \
| sed '$!G' \
| tee >(xclip -selection clipboard)
