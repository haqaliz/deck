pub mod clock;
pub mod devbox;
pub mod feed;
pub mod git;
pub mod livebox;
pub mod logbox;
pub mod market;
pub mod metricbox;
pub mod netbox;
pub mod open;
pub mod prs;
pub mod ship;
pub mod tasks;
pub mod weather;

use std::collections::VecDeque;

use deck_core::livebox::Tier;
use deck_core::paths::Paths;
use deck_core::settings::WidgetSize;
use deck_core::snapshot::{self, FetchOutcome};
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

pub fn link_row(container: &gtk::Box, text: &str, url: &str) -> gtk::LinkButton {
    let link = gtk::LinkButton::with_label(url, &truncate(text, 40));
    link.add_css_class("link-row");
    link.set_halign(gtk::Align::Start);
    container.append(&link);
    link
}

/// Last-known fetch outcome as one short line; the last good snapshot stays
/// visible above it when a refresh fails.
fn truncate(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_owned();
    }
    let mut out: String = text.chars().take(limit.saturating_sub(1)).collect();
    out.push('…');
    out
}

pub fn status_text(paths: &Paths, source: &str) -> String {
    match snapshot::read_status(paths, source).map(|status| status.outcome) {
        Some(FetchOutcome::NotConfigured) => "Configure in Settings".into(),
        Some(FetchOutcome::AuthOrTarget) => "Check the token or target".into(),
        Some(FetchOutcome::Unreachable) => "Offline — showing the last data".into(),
        Some(FetchOutcome::BadResponse) => "The source returned an error".into(),
        Some(FetchOutcome::CredentialsUnavailable) => "Credentials unavailable".into(),
        Some(FetchOutcome::QueryRejected) => "The query was rejected".into(),
        Some(FetchOutcome::Ok) | None => "Waiting for the first fetch…".into(),
    }
}

pub fn format_tokens(value: i64) -> String {
    if value >= 1_000_000 {
        format!("{:.1}M", value as f64 / 1_000_000.0)
    } else if value >= 1_000 {
        format!("{:.1}K", value as f64 / 1_000.0)
    } else {
        value.to_string()
    }
}

pub fn format_money(value: f64) -> String {
    if value >= 100.0 {
        format!("${value:.0}")
    } else if value >= 1.0 {
        format!("${value:.2}")
    } else {
        format!("${value:.3}")
    }
}

/// Small 15-day bar chart for GitBox; zero days stay visible as a baseline.
pub fn draw_bars(cr: &gtk::cairo::Context, width: i32, height: i32, values: &[i64]) {
    let width = width as f64;
    let height = height as f64;
    cr.set_source_rgb(0.10, 0.10, 0.16);
    let _ = cr.paint();
    if values.is_empty() {
        return;
    }
    cr.set_source_rgba(0.5, 0.5, 0.6, 0.25);
    cr.set_line_width(1.0);
    cr.move_to(0.0, height - 1.0);
    cr.line_to(width, height - 1.0);
    let _ = cr.stroke();

    let max = values.iter().copied().max().unwrap_or(0).max(1) as f64;
    let slot = width / values.len() as f64;
    let bar_width = (slot - 2.0).max(1.0);
    cr.set_source_rgb(0.42, 0.62, 0.95);
    for (index, value) in values.iter().enumerate() {
        let bar = (*value as f64 / max) * (height - 4.0);
        if *value > 0 {
            cr.rectangle(
                index as f64 * slot + 1.0,
                height - 2.0 - bar,
                bar_width,
                bar,
            );
        }
    }
    let _ = cr.fill();
}

/// Line-only sparkline for market rows; no axes or background.
pub fn draw_sparkline(cr: &gtk::cairo::Context, width: i32, height: i32, values: &[f64], up: bool) {
    if values.len() < 2 {
        return;
    }
    let width = width as f64;
    let height = height as f64;
    let min = values.iter().copied().fold(f64::INFINITY, f64::min);
    let max = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let span = (max - min).max(1e-9);
    if up {
        cr.set_source_rgb(0.42, 0.78, 0.35);
    } else {
        cr.set_source_rgb(0.96, 0.55, 0.66);
    }
    cr.set_line_width(1.0);
    for (index, value) in values.iter().enumerate() {
        let x = index as f64 / (values.len() - 1) as f64 * width;
        let y = 1.0 + (height - 2.0) * (1.0 - (value - min) / span);
        if index == 0 {
            cr.move_to(x, y);
        } else {
            cr.line_to(x, y);
        }
    }
    let _ = cr.stroke();
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
