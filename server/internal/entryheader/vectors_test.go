package entryheader

import (
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// vectorsPath is spec/test-vectors/entry-format.json, from this package.
var vectorsPath = filepath.Join("..", "..", "..", "spec", "test-vectors", "entry-format.json")

type vector struct {
	Description string                     `json:"description"`
	Kind        string                     `json:"kind"`
	Inputs      map[string]json.RawMessage `json:"inputs"`
	Outputs     map[string]json.RawMessage `json:"outputs"`
}

func loadVectors(t *testing.T) []vector {
	t.Helper()
	data, err := os.ReadFile(vectorsPath)
	if err != nil {
		t.Fatalf("read the test vectors: %v", err)
	}
	var vectors []vector
	if err := json.Unmarshal(data, &vectors); err != nil {
		t.Fatalf("decode the test vectors: %v", err)
	}
	return vectors
}

func field[T any](t *testing.T, fields map[string]json.RawMessage, name string) T {
	t.Helper()
	raw, ok := fields[name]
	if !ok {
		t.Fatalf("no field %q", name)
	}
	var v T
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("field %q: %v", name, err)
	}
	return v
}

func hexField(t *testing.T, fields map[string]json.RawMessage, name string) []byte {
	t.Helper()
	b, err := hex.DecodeString(field[string](t, fields, name))
	if err != nil {
		t.Fatalf("field %q: %v", name, err)
	}
	return b
}

func idField(t *testing.T, fields map[string]json.RawMessage, name string) ID {
	t.Helper()
	id, err := ParseID(field[string](t, fields, name))
	if err != nil {
		t.Fatalf("field %q: %v", name, err)
	}
	return id
}

// headerCodes are the errors a header check finds. A vector that expects
// any other code fails where only a holder of the keys can look: there,
// the header is fine and the server accepts the blob.
var headerCodes = map[Code]bool{
	Malformed:          true,
	NonCanonical:       true,
	UnsupportedVersion: true,
	InvalidEntryDate:   true,
	WrongEntry:         true,
	WrongBook:          true,
	WrongKeyVersion:    true,
	WrongImage:         true,
}

// beyondHeader are vectors whose code a header check could find, but whose
// fault is inside the encrypted payload.
var beyondHeader = map[string]bool{
	"The same Image listed twice in the payload": true,
}

// wantFromServer is what the server's check of a blob in an open vector
// should give: the vector's code, or none when the fault is out of its
// reach.
func wantFromServer(v vector, code Code) Code {
	if !headerCodes[code] || beyondHeader[v.Description] {
		return ""
	}
	return code
}

func TestEntryVectors(t *testing.T) {
	seen := map[string]bool{}
	var seals, opens int
	for _, v := range loadVectors(t) {
		switch v.Kind {
		case "seal-entry":
			seals++
			t.Run(v.Description, func(t *testing.T) {
				header, err := CheckEntryBlob(hexField(t, v.Outputs, "blob"), EntryClaim{
					EntryID:        idField(t, v.Inputs, "entry_id"),
					BookID:         idField(t, v.Inputs, "book_id"),
					BookKeyVersion: field[uint32](t, v.Inputs, "book_key_version"),
				})
				if err != nil {
					t.Fatalf("CheckEntryBlob: %v", err)
				}
				if want := field[string](t, v.Inputs, "entry_date"); header.EntryDate != want {
					t.Errorf("EntryDate = %q, want %q", header.EntryDate, want)
				}
				var e encoder
				header.write(&e)
				if want := hexField(t, v.Outputs, "header"); hex.EncodeToString(e.out) != hex.EncodeToString(want) {
					t.Errorf("header encodes as %x, want %x", e.out, want)
				}
			})
		case "open-entry":
			opens++
			seen[v.Description] = true
			t.Run(v.Description, func(t *testing.T) {
				code := Code(field[string](t, v.Outputs, "error"))
				_, err := CheckEntryBlob(hexField(t, v.Inputs, "blob"), EntryClaim{
					EntryID:        idField(t, v.Inputs, "entry_id"),
					BookID:         idField(t, v.Inputs, "book_id"),
					BookKeyVersion: field[uint32](t, v.Inputs, "book_key_version"),
				})
				if got, want := CodeOf(err), wantFromServer(v, code); got != want {
					t.Errorf("code = %q (%v), want %q (the vector's %q)", got, err, want, code)
				}
			})
		}
	}
	if seals == 0 || opens == 0 {
		t.Fatalf("found %d seal-entry and %d open-entry vectors", seals, opens)
	}
	for description := range beyondHeader {
		if !seen[description] {
			t.Errorf("no vector %q: update beyondHeader", description)
		}
	}
}

func TestImageVectors(t *testing.T) {
	var seals, opens int
	for _, v := range loadVectors(t) {
		switch v.Kind {
		case "seal-image":
			seals++
			t.Run(v.Description, func(t *testing.T) {
				id := idField(t, v.Inputs, "image_id")
				for _, blob := range []string{"full_blob", "thumbnail_blob"} {
					header, err := CheckImageBlob(hexField(t, v.Outputs, blob), id)
					if err != nil {
						t.Fatalf("%s: %v", blob, err)
					}
					if header.ImageID != id {
						t.Errorf("%s: ImageID = %v, want %v", blob, header.ImageID, id)
					}
				}
			})
		case "open-image":
			code := Code(field[string](t, v.Outputs, "error"))
			// The hash is checked first, so these vectors say nothing about
			// the header behind it.
			if code == "hash-mismatch" {
				continue
			}
			opens++
			t.Run(v.Description, func(t *testing.T) {
				image := field[map[string]json.RawMessage](t, v.Inputs, "image")
				_, err := CheckImageBlob(hexField(t, v.Inputs, "blob"), idField(t, image, "image_id"))
				if got, want := CodeOf(err), wantFromServer(v, code); got != want {
					t.Errorf("code = %q (%v), want %q (the vector's %q)", got, err, want, code)
				}
			})
		}
	}
	if seals == 0 || opens == 0 {
		t.Fatalf("found %d seal-image and %d open-image vectors", seals, opens)
	}
}
