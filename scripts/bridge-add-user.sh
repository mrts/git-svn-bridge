#!/bin/sh
while read line; do
	# Simply ignore lines starting with #
	if [ $(echo $line |grep -c ^#) -eq 0 ];then
		export U="$(echo $line|cut -d: -f1)"
		export P="$(echo $line|cut -d: -f2)"
		export N="$(echo $line|cut -d: -f3)"
		export E="$(echo $line|cut -d: -f4)"
		./bridge-add-user.expect "$U" "$P" "$N" "$E"
	fi
done < user-list.txt