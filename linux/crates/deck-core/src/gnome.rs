use std::process::Command;

pub const SCHEMA: &str = "org.gnome.settings-daemon.plugins.media-keys";
pub const KEY_PATH: &str = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/deck/";
const KEYBINDING_SCHEMA: &str = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding";

/// Parses the GVariant array `gsettings get` prints. Tolerates `@as []`,
/// `[]`, and an array of single-quoted paths.
pub fn parse_list(raw: &str) -> Vec<String> {
    let raw = raw.trim().trim_start_matches("@as").trim();
    raw.split('\'')
        .skip(1)
        .step_by(2)
        .map(str::to_owned)
        .collect()
}

pub fn render_list(paths: &[String]) -> String {
    let entries: Vec<String> = paths.iter().map(|path| format!("'{path}'")).collect();
    format!("[{}]", entries.join(", "))
}

/// Returns the new list and whether the path was added.
pub fn merged(raw: &str, path: &str) -> (String, bool) {
    let mut paths = parse_list(raw);
    if paths.iter().any(|existing| existing == path) {
        return (raw.trim().to_owned(), false);
    }
    paths.push(path.to_owned());
    (render_list(&paths), true)
}

fn run(args: &[&str]) -> Result<String, String> {
    let output = Command::new("gsettings")
        .args(args)
        .output()
        .map_err(|error| format!("gsettings: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

/// Writes the GNOME custom keybinding. `<Super>space` matches the labwc
/// default; the command is the CLI so a GUI restart is never required.
pub fn install(command: &str) -> Result<(), String> {
    let current = run(&["get", SCHEMA, "custom-keybindings"])?;
    let (merged_list, _) = merged(&current, KEY_PATH);
    run(&["set", SCHEMA, "custom-keybindings", &merged_list])?;

    let schema = format!("{KEYBINDING_SCHEMA}:{KEY_PATH}");
    let command = command.replace('\'', "");
    run(&["set", &schema, "name", "'Deck search'"])?;
    run(&["set", &schema, "command", &format!("'{command}'")])?;
    run(&["set", &schema, "binding", "'<Super>space'"])?;
    Ok(())
}

/// Removes Deck's custom keybinding from the GNOME list and resets its keys.
pub fn remove() -> Result<bool, String> {
    let current = run(&["get", SCHEMA, "custom-keybindings"])?;
    let paths = parse_list(&current);
    if !paths.iter().any(|path| path == KEY_PATH) {
        return Ok(false);
    }
    let remaining: Vec<String> = paths.into_iter().filter(|path| path != KEY_PATH).collect();
    run(&[
        "set",
        SCHEMA,
        "custom-keybindings",
        &render_list(&remaining),
    ])?;
    let schema = format!("{KEYBINDING_SCHEMA}:{KEY_PATH}");
    let _ = run(&["reset", &schema, "name"]);
    let _ = run(&["reset", &schema, "command"]);
    let _ = run(&["reset", &schema, "binding"]);
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_empty_and_populated_variants() {
        assert!(parse_list("@as []").is_empty());
        assert!(parse_list("[]").is_empty());
        assert_eq!(
            parse_list("['/a/', '/b/']"),
            vec!["/a/".to_string(), "/b/".to_string()]
        );
    }

    #[test]
    fn merge_is_idempotent_and_preserves_existing_bindings() {
        let (once, added) = merged("@as []", KEY_PATH);
        assert!(added);
        assert_eq!(once, format!("['{KEY_PATH}']"));
        let (twice, added_again) = merged(&once, KEY_PATH);
        assert!(!added_again);
        assert_eq!(twice, once);

        let (kept, _) = merged("['/custom/']", KEY_PATH);
        assert!(kept.contains("'/custom/'"));
        assert!(kept.contains(KEY_PATH));
    }
}
