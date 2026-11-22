package entryheader

// maxOffsetMinutes is the largest UTC offset an Entry date may have.
const maxOffsetMinutes = 18 * 60

// validEntryDate reports whether text is an Entry date as spec/entry-format.md
// defines it: YYYY-MM-DDTHH:MM:SS±HH:MM, a date that exists, and an offset of
// at most 18:00, with zero written +00:00.
func validEntryDate(text string) bool {
	// YYYY-MM-DDTHH:MM:SS+HH:MM
	// 0123456789012345678901234
	if len(text) != 25 {
		return false
	}
	for at, c := range map[int]byte{4: '-', 7: '-', 10: 'T', 13: ':', 16: ':', 22: ':'} {
		if text[at] != c {
			return false
		}
	}
	sign := text[19]
	if sign != '+' && sign != '-' {
		return false
	}
	ok := true
	number := func(from, to int) int {
		n := 0
		for i := from; i < to; i++ {
			c := text[i]
			if c < '0' || c > '9' {
				ok = false
				return 0
			}
			n = n*10 + int(c-'0')
		}
		return n
	}
	year, month, day := number(0, 4), number(5, 7), number(8, 10)
	hour, minute, second := number(11, 13), number(14, 16), number(17, 19)
	offsetHours, offsetMinutes := number(20, 22), number(23, 25)
	if !ok {
		return false
	}
	offset := offsetHours*60 + offsetMinutes

	return year >= 1 &&
		month >= 1 && month <= 12 &&
		day >= 1 && day <= daysInMonth(year, month) &&
		hour < 24 && minute < 60 && second < 60 &&
		offsetMinutes < 60 && offset <= maxOffsetMinutes &&
		(sign != '-' || offset != 0)
}

func daysInMonth(year, month int) int {
	switch month {
	case 2:
		if year%4 == 0 && (year%100 != 0 || year%400 == 0) {
			return 29
		}
		return 28
	case 4, 6, 9, 11:
		return 30
	default:
		return 31
	}
}
