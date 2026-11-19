pub mod devbox;
pub mod livebox;
pub mod netbox;

use std::collections::VecDeque;

use deck_core::livebox::Tier;
use deck_core::settings::WidgetSize;
use gtk4 as gtk;
use gtk4::prelude::*;

pub fn metric_label(title: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(&format!("{title}   —")));
    label.add_css_class("metric");
    label.set_halign(gtk::Align::Start);
    label.set_xalign(0.0);
    label
}

pub fn section(container: &gtk::Box, title: &str) {
    let label = gtk::Label::new(Some(title));
    label.add_css_class("section");
    label.set_halign(gtk::Align::Start);
    container.append(&label);
}

pub fn clear(container: &gtk::Box) {
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }
}

pub fn add_row(container: &gtk::Box, text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.add_css_class("subtitle");
    label.set_halign(gtk::Align::Start);
    label.set_ellipsize(gtk::pango::EllipsizeMode::End);
    container.append(&label);
    label
}

pub fn height(size: WidgetSize, small: i32, medium: i32, large: i32) -> i32 {
    match size {
        WidgetSize::Small => small,
        WidgetSize::Medium => medium,
        WidgetSize::Large => large,
    }
}

pub fn apply_tier(label: &gtk::Label, tier: Tier) {
    label.remove_css_class("warn");
    label.remove_css_class("alarm");
    match tier {
        Tier::Normal => {}
        Tier::Warn => label.add_css_class("warn"),
        Tier::Alarm => label.add_css_class("alarm"),
    }
}

/// Shared Cairo chart. `max` clamps the scale; `None` scales to the history,
/// which keeps low-traffic network charts readable.
pub fn draw_chart(
    cr: &gtk::cairo::Context,
    width: i32,
    height: i32,
    series: &[Vec<f64>],
    colors: &[(f64, f64, f64)],
    max: Option<f64>,
) {
    let width = width as f64;
    let height = height as f64;
    cr.set_source_rgb(0.10, 0.10, 0.16);
    let _ = cr.paint();

    cr.set_source_rgba(0.5, 0.5, 0.6, 0.25);
    cr.set_line_width(1.0);
    for step in 0..=4 {
        let y = 1.0 + (height - 2.0) * step as f64 / 4.0;
        cr.move_to(0.0, y);
        cr.line_to(width, y);
        let _ = cr.stroke();
    }

    if series.iter().any(|points| points.len() < 2) {
        return;
    }
    let max = max.unwrap_or_else(|| {
        series
            .iter()
            .flat_map(|points| points.iter())
            .fold(1.0_f64, |max, value| max.max(*value))
    });
    let max = max.max(1.0);

    for (index, points) in series.iter().enumerate() {
        let color = colors.get(index).copied().unwrap_or((0.5, 0.5, 0.5));
        cr.set_source_rgb(color.0, color.1, color.2);
        cr.set_line_width(1.5);
        for (position, value) in points.iter().enumerate() {
            let x = position as f64 / (points.len() - 1) as f64 * width;
            let y = 1.0 + (height - 2.0) * (1.0 - (value / max).clamp(0.0, 1.0));
            if position == 0 {
                cr.move_to(x, y);
            } else {
                cr.line_to(x, y);
            }
        }
        let _ = cr.stroke();
    }
}

pub fn history_series<const N: usize>(history: &VecDeque<[f64; N]>, index: usize) -> Vec<f64> {
    history.iter().map(|sample| sample[index]).collect()
}
