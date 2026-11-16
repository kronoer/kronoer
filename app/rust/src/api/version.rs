//! Information about the Kronoer core.

/// The version of the Kronoer core.
#[flutter_rust_bridge::frb(sync)]
pub fn core_version() -> String {
    kronoer_core::version().to_string()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
