if [$1 = "d"]
	mv $2 $2.disabled
elif [$1 = "e"]
	mv $2 ${2%%.disabled}
fi
