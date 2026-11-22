package entryheader

import (
	"encoding/binary"
	"math"
	"unicode/utf8"
)

// CBOR major types used by the format.
const (
	majorUint  = 0
	majorBytes = 2
	majorText  = 3
	majorArray = 4
)

// decoder reads CBOR items one after another. It accepts any length
// encoding, shortest or not: the caller encodes what it read again and
// compares, as the Rust core does, so a longer form fails as non-canonical
// after every other check.
type decoder struct {
	input []byte
	pos   int
}

// head reads an item's first byte and argument. Indefinite lengths come back
// with indefinite set.
func (d *decoder) head() (major byte, arg uint64, indefinite bool, err error) {
	if d.pos >= len(d.input) {
		return 0, 0, false, errCode(Malformed)
	}
	first := d.input[d.pos]
	d.pos++
	major = first >> 5
	info := first & 0x1f
	var size int
	switch {
	case info < 24:
		return major, uint64(info), false, nil
	case info == 24:
		size = 1
	case info == 25:
		size = 2
	case info == 26:
		size = 4
	case info == 27:
		size = 8
	case info == 31:
		return major, 0, true, nil
	default:
		return 0, 0, false, errCode(Malformed)
	}
	if len(d.input)-d.pos < size {
		return 0, 0, false, errCode(Malformed)
	}
	raw := d.input[d.pos : d.pos+size]
	d.pos += size
	switch size {
	case 1:
		arg = uint64(raw[0])
	case 2:
		arg = uint64(binary.BigEndian.Uint16(raw))
	case 4:
		arg = uint64(binary.BigEndian.Uint32(raw))
	default:
		arg = binary.BigEndian.Uint64(raw)
	}
	return major, arg, false, nil
}

// array reads the start of an array and returns its length. An indefinite
// length is not deterministic.
func (d *decoder) array() (uint64, error) {
	major, n, indefinite, err := d.head()
	if err != nil {
		return 0, err
	}
	if major != majorArray {
		return 0, errCode(Malformed)
	}
	if indefinite {
		return 0, errCode(NonCanonical)
	}
	return n, nil
}

func (d *decoder) uint() (uint64, error) {
	major, n, indefinite, err := d.head()
	if err != nil {
		return 0, err
	}
	if major != majorUint || indefinite {
		return 0, errCode(Malformed)
	}
	return n, nil
}

// string reads a definite-length byte or text string of the given major type.
func (d *decoder) string(want byte) ([]byte, error) {
	major, n, indefinite, err := d.head()
	if err != nil {
		return nil, err
	}
	if major != want || indefinite || n > uint64(len(d.input)-d.pos) {
		return nil, errCode(Malformed)
	}
	s := d.input[d.pos : d.pos+int(n)]
	d.pos += int(n)
	return s, nil
}

func (d *decoder) bytes() ([]byte, error) {
	return d.string(majorBytes)
}

// bytesOf reads a byte string that must be exactly n bytes long.
func (d *decoder) bytesOf(n int) ([]byte, error) {
	b, err := d.bytes()
	if err != nil {
		return nil, err
	}
	if len(b) != n {
		return nil, errCode(Malformed)
	}
	return b, nil
}

func (d *decoder) text() (string, error) {
	b, err := d.string(majorText)
	if err != nil {
		return "", err
	}
	if !utf8.Valid(b) {
		return "", errCode(Malformed)
	}
	return string(b), nil
}

// finish fails unless the whole input was read.
func (d *decoder) finish() error {
	if d.pos != len(d.input) {
		return errCode(Malformed)
	}
	return nil
}

// encoder writes deterministic CBOR: every argument in its shortest form.
type encoder struct {
	out []byte
}

func (e *encoder) head(major byte, arg uint64) {
	m := major << 5
	switch {
	case arg < 24:
		e.out = append(e.out, m|byte(arg))
	case arg <= math.MaxUint8:
		e.out = append(e.out, m|24, byte(arg))
	case arg <= math.MaxUint16:
		e.out = binary.BigEndian.AppendUint16(append(e.out, m|25), uint16(arg))
	case arg <= math.MaxUint32:
		e.out = binary.BigEndian.AppendUint32(append(e.out, m|26), uint32(arg))
	default:
		e.out = binary.BigEndian.AppendUint64(append(e.out, m|27), arg)
	}
}

func (e *encoder) array(n int)   { e.head(majorArray, uint64(n)) }
func (e *encoder) uint(n uint64) { e.head(majorUint, n) }

func (e *encoder) bytes(b []byte) {
	e.head(majorBytes, uint64(len(b)))
	e.out = append(e.out, b...)
}

func (e *encoder) text(s string) {
	e.head(majorText, uint64(len(s)))
	e.out = append(e.out, s...)
}
