use std::sync::mpsc::Sender;

use ksni::blocking::TrayMethods;

use crate::Command;

struct DeckTray {
    tx: Sender<Command>,
}

impl ksni::Tray for DeckTray {
    fn id(&self) -> String {
        "deck".into()
    }

    fn title(&self) -> String {
        "Deck".into()
    }

    fn icon_name(&self) -> String {
        "computer".into()
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::*;
        vec![
            StandardItem {
                label: "Search".into(),
                icon_name: "system-search".into(),
                activate: Box::new(|this: &mut Self| {
                    let _ = this.tx.send(Command::ToggleSearch);
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Settings".into(),
                icon_name: "preferences-system".into(),
                activate: Box::new(|this: &mut Self| {
                    let _ = this.tx.send(Command::ShowSettings);
                }),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Quit".into(),
                icon_name: "application-exit".into(),
                activate: Box::new(|this: &mut Self| {
                    let _ = this.tx.send(Command::Quit);
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

pub fn spawn(tx: Sender<Command>) {
    match (DeckTray { tx }).spawn() {
        Ok(handle) => std::mem::forget(handle),
        Err(error) => eprintln!("deck-gui: tray unavailable: {error}"),
    }
}
