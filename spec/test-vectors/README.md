# Test vectors

Known inputs and expected outputs for the documents in `spec/`. An implementation is compatible only if it reproduces every vector.

- One JSON file per document, with the same name: `entry-format.md` → `entry-format.json`.
- Each file holds a list of vectors. Each vector has a `description` and named inputs and outputs.
- Bytes are lowercase hex strings. Text is UTF-8 JSON strings.
- Every value that is normally random, such as keys and nonces, is given as an input, so each output is deterministic.
- Vectors are generated and checked by the tests in `core/`. Never edit an expected output by hand.
- The server's header parser (`server/internal/entryheader`) also runs the Entry and Image vectors, for the checks it can make without keys.

Vectors are added together with the document they test.