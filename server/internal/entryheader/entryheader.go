// Package entryheader reads the readable headers of Entry blobs and Image
// blobs, as spec/entry-format.md defines them, so the server can reject an
// upload whose header does not match what the request claims.
//
// It never touches the encrypted parts: the server holds no key that can
// open them. It decodes a blob with the same strictness as a reader in the
// Rust core (deterministic CBOR only, format-version checked first, a valid
// Entry date, nothing after the blob), and the shared test vectors in
// spec/test-vectors/ keep the two in step.
package entryheader

import (
	"bytes"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
)

// FormatVersion is the only format-version this package reads.
const FormatVersion = 1

// FormatVersions are the format versions this package reads, for clients to
// learn before they upload.
func FormatVersions() []uint32 {
	return []uint32{FormatVersion}
}

// Sizes from spec/entry-format.md.
const (
	idLen             = 16
	nonceLen          = 24
	sealedEntryKeyLen = 48
	tagLen            = 16
	entryHeaderLen    = 5
	entryBlobLen      = 5
	imageHeaderLen    = 2
	imageBlobLen      = 3
)

// Code names a failure with the error codes of spec/entry-format.md.
type Code string

// The codes a header check can fail with. The other codes of the spec
// (decryption-failed, hash-mismatch) need keys or the Image reference, which
// the server never has.
const (
	Malformed          Code = "malformed"
	NonCanonical       Code = "non-canonical"
	UnsupportedVersion Code = "unsupported-version"
	InvalidEntryDate   Code = "invalid-entry-date"
	WrongEntry         Code = "wrong-entry"
	WrongBook          Code = "wrong-book"
	WrongKeyVersion    Code = "wrong-key-version"
	WrongImage         Code = "wrong-image"
)

// Error is a blob that fails a check.
type Error struct {
	Code Code
	// Version is the format-version read, for UnsupportedVersion.
	Version uint64
}

func (e *Error) Error() string {
	if e.Code == UnsupportedVersion {
		return fmt.Sprintf("blob header: %s %d", e.Code, e.Version)
	}
	return "blob header: " + string(e.Code)
}

func errCode(code Code) error {
	return &Error{Code: code}
}

// CodeOf returns the code of err, or "" if it is not an *Error.
func CodeOf(err error) Code {
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

// ID is an Entry, Book, or Image ID: 16 bytes.
type ID [idLen]byte

// ParseID reads the text form of an ID: 32 lowercase hexadecimal digits.
func ParseID(text string) (ID, error) {
	var id ID
	valid := len(text) == 2*idLen
	for i := 0; valid && i < len(text); i++ {
		c := text[i]
		valid = '0' <= c && c <= '9' || 'a' <= c && c <= 'f'
	}
	if !valid {
		return id, fmt.Errorf("id %q is not 32 lowercase hex digits", text)
	}
	_, err := hex.Decode(id[:], []byte(text))
	return id, err
}

// String is the text form of the ID.
func (id ID) String() string {
	return hex.EncodeToString(id[:])
}

// EntryHeader is the readable header of an Entry blob.
type EntryHeader struct {
	EntryID        ID
	BookID         ID
	BookKeyVersion uint32
	// EntryDate is the Entry date as written, for example
	// "2026-11-17T23:30:00+07:00".
	EntryDate string
}

// EntryClaim is what an upload says an Entry blob is.
type EntryClaim struct {
	EntryID        ID
	BookID         ID
	BookKeyVersion uint32
}

// CheckEntryBlob reads blob's header and checks it against claim: the Entry
// ID, then the Book ID, then the Book key version.
func CheckEntryBlob(blob []byte, claim EntryClaim) (EntryHeader, error) {
	header, err := ReadEntryBlob(blob)
	if err != nil {
		return EntryHeader{}, err
	}
	switch {
	case header.EntryID != claim.EntryID:
		return EntryHeader{}, errCode(WrongEntry)
	case header.BookID != claim.BookID:
		return EntryHeader{}, errCode(WrongBook)
	case header.BookKeyVersion != claim.BookKeyVersion:
		return EntryHeader{}, errCode(WrongKeyVersion)
	}
	return header, nil
}

// ReadEntryBlob decodes a whole Entry blob, strictly, and returns its header.
// The encrypted fields are checked for their sizes only.
func ReadEntryBlob(blob []byte) (EntryHeader, error) {
	d := &decoder{input: blob}
	n, err := d.array()
	if err != nil {
		return EntryHeader{}, err
	}
	header, err := readEntryHeader(d)
	if err != nil {
		return EntryHeader{}, err
	}
	if n != entryBlobLen {
		return EntryHeader{}, errCode(Malformed)
	}
	entryKeyNonce, err := d.bytesOf(nonceLen)
	if err != nil {
		return EntryHeader{}, err
	}
	sealedEntryKey, err := d.bytesOf(sealedEntryKeyLen)
	if err != nil {
		return EntryHeader{}, err
	}
	payloadNonce, err := d.bytesOf(nonceLen)
	if err != nil {
		return EntryHeader{}, err
	}
	sealedPayload, err := d.bytes()
	if err != nil {
		return EntryHeader{}, err
	}
	if len(sealedPayload) < tagLen {
		return EntryHeader{}, errCode(Malformed)
	}
	if err := d.finish(); err != nil {
		return EntryHeader{}, err
	}

	var e encoder
	e.array(entryBlobLen)
	header.write(&e)
	e.bytes(entryKeyNonce)
	e.bytes(sealedEntryKey)
	e.bytes(payloadNonce)
	e.bytes(sealedPayload)
	if !bytes.Equal(e.out, blob) {
		return EntryHeader{}, errCode(NonCanonical)
	}
	return header, nil
}

// readFormatVersion reads the start of a header: its length, then the
// format-version, checked before anything after it.
func readFormatVersion(d *decoder, headerLen uint64) error {
	n, err := d.array()
	if err != nil {
		return err
	}
	version, err := d.uint()
	if err != nil {
		return err
	}
	if version != FormatVersion {
		return &Error{Code: UnsupportedVersion, Version: version}
	}
	if n != headerLen {
		return errCode(Malformed)
	}
	return nil
}

func readEntryHeader(d *decoder) (EntryHeader, error) {
	var h EntryHeader
	if err := readFormatVersion(d, entryHeaderLen); err != nil {
		return h, err
	}
	entryID, err := d.bytesOf(idLen)
	if err != nil {
		return h, err
	}
	bookID, err := d.bytesOf(idLen)
	if err != nil {
		return h, err
	}
	keyVersion, err := d.uint()
	if err != nil {
		return h, err
	}
	if keyVersion == 0 || keyVersion > math.MaxUint32 {
		return h, errCode(Malformed)
	}
	date, err := d.text()
	if err != nil {
		return h, err
	}
	if !validEntryDate(date) {
		return h, errCode(InvalidEntryDate)
	}
	h.EntryID = ID(entryID)
	h.BookID = ID(bookID)
	h.BookKeyVersion = uint32(keyVersion)
	h.EntryDate = date
	return h, nil
}

func (h EntryHeader) write(e *encoder) {
	e.array(entryHeaderLen)
	e.uint(FormatVersion)
	e.bytes(h.EntryID[:])
	e.bytes(h.BookID[:])
	e.uint(uint64(h.BookKeyVersion))
	e.text(h.EntryDate)
}

// ImageHeader is the readable header of an Image blob. The full image and
// the thumbnail of one Image have the same header.
type ImageHeader struct {
	ImageID ID
}

// CheckImageBlob reads blob's header and checks that it names imageID.
func CheckImageBlob(blob []byte, imageID ID) (ImageHeader, error) {
	header, err := ReadImageBlob(blob)
	if err != nil {
		return ImageHeader{}, err
	}
	if header.ImageID != imageID {
		return ImageHeader{}, errCode(WrongImage)
	}
	return header, nil
}

// ReadImageBlob decodes a whole Image blob, strictly, and returns its header.
// The encrypted fields are checked for their sizes only.
func ReadImageBlob(blob []byte) (ImageHeader, error) {
	d := &decoder{input: blob}
	n, err := d.array()
	if err != nil {
		return ImageHeader{}, err
	}
	if err := readFormatVersion(d, imageHeaderLen); err != nil {
		return ImageHeader{}, err
	}
	imageID, err := d.bytesOf(idLen)
	if err != nil {
		return ImageHeader{}, err
	}
	if n != imageBlobLen {
		return ImageHeader{}, errCode(Malformed)
	}
	nonce, err := d.bytesOf(nonceLen)
	if err != nil {
		return ImageHeader{}, err
	}
	sealedImage, err := d.bytes()
	if err != nil {
		return ImageHeader{}, err
	}
	if len(sealedImage) < tagLen {
		return ImageHeader{}, errCode(Malformed)
	}
	if err := d.finish(); err != nil {
		return ImageHeader{}, err
	}

	var e encoder
	e.array(imageBlobLen)
	e.array(imageHeaderLen)
	e.uint(FormatVersion)
	e.bytes(imageID)
	e.bytes(nonce)
	e.bytes(sealedImage)
	if !bytes.Equal(e.out, blob) {
		return ImageHeader{}, errCode(NonCanonical)
	}
	return ImageHeader{ImageID: ID(imageID)}, nil
}
