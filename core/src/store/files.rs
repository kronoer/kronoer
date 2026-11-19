//! Image files: one sealed Image blob per file, named by Image ID and variant.

use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use crate::{Id, ImageVariant};

const TEMPORARY: &str = "tmp";

pub(crate) struct ImageFiles {
    dir: PathBuf,
}

impl ImageFiles {
    pub(crate) fn open(dir: PathBuf) -> std::io::Result<ImageFiles> {
        fs::create_dir_all(&dir)?;
        Ok(ImageFiles { dir })
    }

    pub(crate) fn path(&self, id: Id, variant: ImageVariant) -> PathBuf {
        let suffix = match variant {
            ImageVariant::Full => "full",
            ImageVariant::Thumbnail => "thumb",
        };
        self.dir.join(format!("{id}.{suffix}"))
    }

    /// Writes a blob so that the file either holds all of it or does not exist: it is written to
    /// a temporary file, flushed to disk, and renamed into place. On Unix the directory is flushed
    /// too, so the rename survives a power loss before the database commit that refers to it.
    pub(crate) fn write(&self, id: Id, variant: ImageVariant, blob: &[u8]) -> std::io::Result<()> {
        let path = self.path(id, variant);
        let temporary = path.with_extension(format!(
            "{}.{TEMPORARY}",
            path.extension().unwrap().to_string_lossy()
        ));
        let result = (|| {
            let mut file = File::create(&temporary)?;
            file.write_all(blob)?;
            file.sync_all()?;
            fs::rename(&temporary, &path)?;
            #[cfg(unix)]
            File::open(&self.dir)?.sync_all()?;
            Ok(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result
    }

    pub(crate) fn read(&self, id: Id, variant: ImageVariant) -> std::io::Result<Vec<u8>> {
        fs::read(self.path(id, variant))
    }

    /// Removes both files of an Image. Files that are already gone are fine; anything left behind
    /// is removed later as an orphan.
    pub(crate) fn remove(&self, id: Id) {
        for variant in [ImageVariant::Full, ImageVariant::Thumbnail] {
            let _ = fs::remove_file(self.path(id, variant));
        }
    }

    /// Removes files older than `age` whose Image is not in `keep`, and temporary files left by a
    /// write that did not finish.
    pub(crate) fn remove_orphans(
        &self,
        keep: impl Fn(Id) -> bool,
        age: Duration,
    ) -> std::io::Result<usize> {
        let now = SystemTime::now();
        let mut removed = 0;
        for item in fs::read_dir(&self.dir)? {
            let item = item?;
            let path = item.path();
            let old_enough = item
                .metadata()
                .and_then(|m| m.modified())
                .map(|modified| now.duration_since(modified).unwrap_or_default() >= age)
                .unwrap_or(false);
            if old_enough && !image_id(&path).is_some_and(&keep) && fs::remove_file(&path).is_ok() {
                removed += 1;
            }
        }
        Ok(removed)
    }
}

/// The Image ID a finished image file belongs to. Temporary and unknown files belong to none.
fn image_id(path: &Path) -> Option<Id> {
    let name = path.file_name()?.to_str()?;
    let (id, suffix) = name.split_once('.')?;
    match suffix {
        "full" | "thumb" => Id::from_hex(id).ok(),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_files_by_image_id_and_variant() {
        let files = ImageFiles {
            dir: PathBuf::from("images"),
        };
        let id = Id::from_bytes([0xab; 16]);

        assert_eq!(
            files.path(id, ImageVariant::Full),
            PathBuf::from("images").join(format!("{id}.full"))
        );
        assert_eq!(image_id(&files.path(id, ImageVariant::Thumbnail)), Some(id));
        assert_eq!(image_id(Path::new(&format!("{id}.full.tmp"))), None);
        assert_eq!(image_id(Path::new("notes.txt")), None);
    }
}
