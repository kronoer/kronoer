package entryheader

import (
	"bytes"
	"testing"
)

var (
	entryID = ID{0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef}
	bookID  = ID{0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf}
	imageID = ID{0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf}
	claim   = EntryClaim{EntryID: entryID, BookID: bookID, BookKeyVersion: 1}
)

// entryBlob is an Entry blob with the given header fields and filler where
// the encrypted parts go.
func entryBlob(version, keyVersion uint64, date string) []byte {
	var e encoder
	e.array(entryBlobLen)
	e.array(entryHeaderLen)
	e.uint(version)
	e.bytes(entryID[:])
	e.bytes(bookID[:])
	e.uint(keyVersion)
	e.text(date)
	e.bytes(make([]byte, nonceLen))
	e.bytes(make([]byte, sealedEntryKeyLen))
	e.bytes(make([]byte, nonceLen))
	e.bytes(make([]byte, tagLen+5))
	return e.out
}

// imageBlob is an Image blob for id, with sealedLen bytes of filler as the
// sealed image.
func imageBlob(id ID, sealedLen int) []byte {
	var e encoder
	e.array(imageBlobLen)
	e.array(imageHeaderLen)
	e.uint(FormatVersion)
	e.bytes(id[:])
	e.bytes(make([]byte, nonceLen))
	e.bytes(make([]byte, sealedLen))
	return e.out
}

const date = "2026-11-17T23:30:00+07:00"

func TestCheckEntryBlobReadsTheHeader(t *testing.T) {
	header, err := CheckEntryBlob(entryBlob(1, 1, date), claim)
	if err != nil {
		t.Fatal(err)
	}
	want := EntryHeader{EntryID: entryID, BookID: bookID, BookKeyVersion: 1, EntryDate: date}
	if header != want {
		t.Errorf("header = %+v, want %+v", header, want)
	}
}

func TestCheckEntryBlobComparesTheClaim(t *testing.T) {
	blob := entryBlob(1, 1, date)
	for _, tc := range []struct {
		name  string
		claim EntryClaim
		want  Code
	}{
		{"another Entry", EntryClaim{EntryID: bookID, BookID: bookID, BookKeyVersion: 1}, WrongEntry},
		{"another Book", EntryClaim{EntryID: entryID, BookID: entryID, BookKeyVersion: 1}, WrongBook},
		{"another key version", EntryClaim{EntryID: entryID, BookID: bookID, BookKeyVersion: 2}, WrongKeyVersion},
		// The Entry ID is checked first.
		{"all wrong", EntryClaim{BookKeyVersion: 3}, WrongEntry},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := CheckEntryBlob(blob, tc.claim)
			if got := CodeOf(err); got != tc.want {
				t.Errorf("code = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestReadEntryBlobRejects(t *testing.T) {
	good := entryBlob(1, 1, date)
	for _, tc := range []struct {
		name string
		blob []byte
		want Code
	}{
		{"nothing", nil, Malformed},
		{"a cut-off blob", good[:len(good)-1], Malformed},
		{"a byte after the blob", append(bytes.Clone(good), 0), Malformed},
		{"a map instead of an array", append([]byte{0xa0}, good[1:]...), Malformed},
		{"an indefinite-length blob", append(append([]byte{0x9f}, good[1:]...), 0xff), NonCanonical},
		{"key version 0", entryBlob(1, 0, date), Malformed},
		{"a key version over 32 bits", entryBlob(1, 1<<32, date), Malformed},
		{"format version 2", entryBlob(2, 1, date), UnsupportedVersion},
		// The version comes first: nothing after it is read.
		{"format version 2 and a broken date", entryBlob(2, 1, "not a date"), UnsupportedVersion},
		{"an invalid Entry date", entryBlob(1, 1, "2026-02-29T00:00:00+00:00"), InvalidEntryDate},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ReadEntryBlob(tc.blob)
			if got := CodeOf(err); got != tc.want {
				t.Errorf("code = %q (%v), want %q", got, err, tc.want)
			}
		})
	}
}

func TestReadEntryBlobRejectsLongerForms(t *testing.T) {
	var e encoder
	e.array(entryBlobLen)
	e.array(entryHeaderLen)
	e.uint(FormatVersion)
	e.bytes(entryID[:])
	e.bytes(bookID[:])
	e.out = append(e.out, 0x18, 0x01) // 1 in two bytes
	e.text(date)
	e.bytes(make([]byte, nonceLen))
	e.bytes(make([]byte, sealedEntryKeyLen))
	e.bytes(make([]byte, nonceLen))
	e.bytes(make([]byte, tagLen))

	_, err := ReadEntryBlob(e.out)
	if got := CodeOf(err); got != NonCanonical {
		t.Errorf("code = %q, want %q", got, NonCanonical)
	}
}

func TestReadEntryBlobRejectsABadUTF8Date(t *testing.T) {
	blob := entryBlob(1, 1, date)
	at := bytes.Index(blob, []byte(date))
	blob[at] = 0xff
	_, err := ReadEntryBlob(blob)
	if got := CodeOf(err); got != Malformed {
		t.Errorf("code = %q, want %q", got, Malformed)
	}
}

func TestErrorTellsTheVersion(t *testing.T) {
	_, err := ReadEntryBlob(entryBlob(7, 1, date))
	if got, want := err.Error(), "blob header: unsupported-version 7"; got != want {
		t.Errorf("Error() = %q, want %q", got, want)
	}
}

func TestCheckImageBlob(t *testing.T) {
	header, err := CheckImageBlob(imageBlob(imageID, tagLen), imageID)
	if err != nil {
		t.Fatal(err)
	}
	if header.ImageID != imageID {
		t.Errorf("ImageID = %v, want %v", header.ImageID, imageID)
	}

	_, err = CheckImageBlob(imageBlob(entryID, tagLen), imageID)
	if got := CodeOf(err); got != WrongImage {
		t.Errorf("another Image: code = %q, want %q", got, WrongImage)
	}

	if _, err := ReadImageBlob(imageBlob(imageID, tagLen-1)); CodeOf(err) != Malformed {
		t.Errorf("a short sealed image: %v, want %q", err, Malformed)
	}
}

func TestValidEntryDate(t *testing.T) {
	for _, text := range []string{
		"2026-11-17T23:30:00+07:00",
		"2026-11-17T00:00:00+00:00",
		"2024-02-29T12:00:00-03:30",
		"2000-02-29T12:00:00+05:45",
		"0001-01-01T00:00:00+18:00",
		"9999-12-31T23:59:59-18:00",
	} {
		if !validEntryDate(text) {
			t.Errorf("rejects %q", text)
		}
	}
	for _, text := range []string{
		"",
		"2026-11-17T23:30:00Z",
		"2026-11-17T23:30:00.000+07:00",
		"2026-11-17 23:30:00+07:00",
		"2026-11-17t23:30:00+07:00",
		"2026-11-17T23:30+07:00",
		"0000-01-01T00:00:00+00:00",
		"2026-00-10T00:00:00+00:00",
		"2026-13-10T00:00:00+00:00",
		"2026-02-29T00:00:00+00:00",
		"1900-02-29T00:00:00+00:00",
		"2026-04-31T00:00:00+00:00",
		"2026-11-17T24:00:00+00:00",
		"2026-11-17T23:60:00+00:00",
		"2026-11-17T23:59:60+00:00",
		"2026-11-17T23:30:00-00:00",
		"2026-11-17T23:30:00+18:01",
		"2026-11-17T23:30:00+07:60",
		"2026-11-17T23:30:00*07:00",
		"2026-1a-17T23:30:00+07:00",
	} {
		if validEntryDate(text) {
			t.Errorf("accepts %q", text)
		}
	}
}

func TestParseID(t *testing.T) {
	id, err := ParseID("e0e1e2e3e4e5e6e7e8e9eaebecedeeef")
	if err != nil || id != entryID {
		t.Fatalf("ParseID = %v, %v", id, err)
	}
	if id.String() != "e0e1e2e3e4e5e6e7e8e9eaebecedeeef" {
		t.Errorf("String() = %q", id.String())
	}
	for _, text := range []string{"", "E0E1E2E3E4E5E6E7E8E9EAEBECEDEEEF", "e0e1", "g0e1e2e3e4e5e6e7e8e9eaebecedeeef"} {
		if _, err := ParseID(text); err == nil {
			t.Errorf("accepts %q", text)
		}
	}
}

func TestFormatVersions(t *testing.T) {
	versions := FormatVersions()
	if len(versions) != 1 || versions[0] != FormatVersion {
		t.Errorf("FormatVersions() = %v", versions)
	}
	// Callers may change what they get.
	versions[0] = 9
	if FormatVersions()[0] != FormatVersion {
		t.Error("FormatVersions shares its slice")
	}
}
