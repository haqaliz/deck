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
        "deck".into()
    }

    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        let bytes = include_bytes!("../../../assets/icons/deck-32.png");
        let Ok(decoder) = png::Decoder::new(std::io::Cursor::new(bytes)).read_info() else {
            return Vec::new();
        };
        let mut reader = decoder;
        let mut buffer = vec![0; reader.output_buffer_size()];
        let Ok(info) = reader.next_frame(&mut buffer) else {
            return Vec::new();
        };
        let rgba = &buffer[..info.buffer_size()];
        let mut data = Vec::with_capacity(rgba.len());
        for pixel in rgba.chunks_exact(4) {
            data.extend_from_slice(&[pixel[3], pixel[0], pixel[1], pixel[2]]);
        }
        vec![ksni::Icon {
            width: info.width as i32,
            height: info.height as i32,
            data,
        }]
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
